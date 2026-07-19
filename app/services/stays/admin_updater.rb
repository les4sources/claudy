module Stays
  # Mise à jour de la composition d'un séjour existant depuis le CRUD admin
  # (epic #66, Phase 1). Symétrique de `Reservations::Builder` (création) mais
  # côté édition : on RÉCONCILIE l'occupation d'hébergement et les activités du
  # séjour à partir d'un `Reservations::Draft` reconstruit depuis le formulaire —
  # toujours SANS Stripe et sans email de confirmation forcé.
  #
  # Choix de conception :
  #   - Le CLIENT est upserté par email (même mécanisme que le Builder) : que
  #     l'admin sélectionne un client existant ou en crée un à la volée, le
  #     formulaire remplit les coordonnées du draft, et on retrouve/complète le
  #     `Customer` par son email normalisé.
  #   - L'HÉBERGEMENT : on met à jour le `Booking` d'occupation existant, ou on en
  #     crée un s'il n'y en a pas. On NE TOUCHE PAS au `status`/`email` du Booking
  #     à l'édition (ces deux changements déclenchent l'email client via
  #     `Booking#notify_customer_on_update`) — l'admin ne doit jamais spammer le
  #     client en éditant la compo. Le statut fait foi au niveau du Stay.
  #   - Les ACTIVITÉS : réconciliation ensembliste, bornée au périmètre de
  #     l'utilisateur (`ExperienceAvailability.for_user`) — un porteur n'annule et
  #     ne crée que sur SES créneaux, jamais sur ceux d'un autre.
  #   - Le TOTAL et les DATES sont recalculés par `Stay#recompute_aggregates!`
  #     (source unique déjà éprouvée : bookables + activités actives).
  class AdminUpdater < ServiceBase
    include SpaceComposition
    include CampingComposition
    include MealComposition

    class Invalid < StandardError; end

    attr_reader :stay, :availability_warning

    def initialize(stay:, draft:, status: nil, skip_availability: false, user: nil)
      @stay = stay
      @draft = draft
      @requested_status = status
      @skip_availability = skip_availability
      @user = user
      @report_errors = true
    end

    def run
      run!
      true
    rescue Invalid => e
      set_error_message(e.message)
      false
    rescue => e
      Sentry.capture_exception(e)
      set_error_message("Une erreur est survenue lors de la mise à jour du séjour.")
      false
    end

    def run!
      validate!
      ActiveRecord::Base.transaction do
        @stay.update!(customer: upsert_customer!, status: stay_status)
        reconcile_lodging!
        reconcile_spaces!
        reconcile_camping!
        reconcile_van!
        reconcile_meals!(@stay, @draft)
        reconcile_experiences!
        @stay.recompute_aggregates!
      end
      true
    end

    private

    def validate!
      # Nuits requises UNIQUEMENT pour les réservables à la nuit (hébergement,
      # camping, van). Les compositions sans nuitée — espace en journée sèche
      # (0 nuit), activités seules, repas seuls — sont légitimes (issue #80).
      raise_invalid("Veuillez choisir des dates valides.") if requires_nights? && @draft.nights < 1
      # La contrainte de composition s'élargit (issue #80) : un séjour est valide
      # dès qu'il porte AU MOINS un hébergement, un espace, du camping/van, une
      # activité OU un repas. Les activités seules et repas seuls sont désormais
      # des compositions légitimes (validé par Michael).
      unless @draft.lodging.present? || draft_has_spaces?(@draft) ||
             draft_has_camping?(@draft) || draft_has_van?(@draft) ||
             @draft.bookable_experiences? || draft_has_meals?(@draft)
        raise_invalid("Veuillez sélectionner un hébergement, un espace, un emplacement camping/van, une activité ou un repas.")
      end
      unless Customer.exploitable_email?(@draft.email)
        raise_invalid("Veuillez préciser une adresse email valide pour le client.")
      end
      check_availability!
      check_space_availability!
      check_outdoor_capacity!
    end

    # Réservables facturés À LA NUIT : ils exigent au moins une nuit. Espaces
    # (forfait date+période), activités et repas n'en exigent pas (issue #80).
    def requires_nights?
      @draft.lodging.present? || draft_has_camping?(@draft) || draft_has_van?(@draft)
    end

    # Camping / van : capacité globale (epic #66, Phase 3), en ignorant les
    # réservables PROPRES au séjour (sinon l'édition d'un séjour camping-seul se
    # bloquerait elle-même). Même logique de force que l'hébergement/espaces.
    def check_outdoor_capacity!
      messages = [
        camping_capacity_message(@draft, excluding_id: existing_camping_booking(@stay)&.id),
        van_capacity_message(@draft,     excluding_id: existing_van_booking(@stay)&.id)
      ].compact
      return if messages.empty?

      if @skip_availability
        forced = messages.map { |m| "#{m} — séjour enregistré en forçant la disponibilité." }
        @availability_warning = [@availability_warning, *forced].compact.join(" ")
      else
        raise_invalid(messages.join(" "))
      end
    end

    def check_availability!
      return if @draft.lodging.blank?
      return if @draft.lodging.available_between?(@draft.arrival_date, @draft.departure_date)

      if @skip_availability
        @availability_warning =
          "Ces dates ne sont plus disponibles pour #{@draft.lodging.name} — " \
          "séjour enregistré en forçant la disponibilité (surbooking / saisie a posteriori)."
      else
        raise_invalid("Ces dates ne sont plus disponibles pour cet hébergement.")
      end
    end

    # Dispo espaces capacity-aware (`Space#available_on?`), même logique de force
    # que l'hébergement. On ignore les créneaux DÉJÀ portés par le SpaceBooking du
    # séjour (sinon l'édition d'un séjour espaces-seuls se bloquerait elle-même).
    def check_space_availability!
      specs     = space_reservation_specs(@draft)
      own       = own_space_reservation_keys
      conflicts = space_availability_conflicts(specs)
                    .reject { |c| own.include?([c[:space].id, c[:date]]) }
      return if conflicts.empty?

      names = conflicts.map { |c| c[:space].name }.uniq.join(", ")
      if @skip_availability
        message = "Espace(s) déjà complet(s) à ces dates : #{names} — " \
                  "séjour enregistré en forçant la disponibilité."
        @availability_warning = [@availability_warning, message].compact.join(" ")
      else
        raise_invalid("Espace(s) déjà complet(s) à ces dates : #{names}.")
      end
    end

    # (space_id, date) déjà réservés par le SpaceBooking courant du séjour.
    def own_space_reservation_keys
      sb = existing_space_booking(@stay)
      return [].to_set if sb.nil?
      sb.space_reservations.map { |r| [r.space_id, r.date] }.to_set
    end

    def upsert_customer!
      email = Customer.normalize_email(@draft.email)
      customer = Customer.where(email: email).first_or_initialize
      customer.email = email
      customer.first_name = @draft.first_name if customer.first_name.blank?
      customer.last_name  = @draft.last_name  if customer.last_name.blank?
      customer.phone      = @draft.phone      if customer.phone.blank?
      customer.save!
      customer
    end

    def reconcile_lodging!
      booking = existing_lodging_booking

      # Séjour « espaces seuls » (epic #66, Phase 2) : plus d'hébergement au
      # draft → on détache et libère l'occupation existante (soft-delete du
      # StayItem ET du Booking, pour rendre les dates au calendrier).
      if @draft.lodging.blank?
        if booking
          @stay.stay_items.where(bookable_type: "Booking").each { |i| i.soft_delete!(validate: false) }
          booking.soft_delete!(validate: false)
        end
        return
      end

      # Prix de l'hébergement PUR (epic #66, Phase 3) : hors espaces, hors
      # camping/van/repas (chacun sur son propre modèle) et hors activités.
      # Additionner tous les réservables + repas redonne exactement le total prévu.
      price = @draft.quote.lodging_only_cents

      if booking
        # NB : ni `status` ni `email` ici — voir l'en-tête de classe (anti-email).
        booking.update!(
          lodging_id:        @draft.lodging_id,
          from_date:         @draft.arrival_date,
          to_date:           @draft.departure_date,
          adults:            [@draft.adults, 1].max,
          children:          @draft.children.to_i,
          group_name:        @draft.group_name,
          firstname:         @draft.first_name,
          lastname:          @draft.last_name,
          phone:             @draft.phone,
          price_cents:       price,
          shown_price_cents: price
        )
      else
        booking = Booking.new(
          firstname:         @draft.first_name,
          lastname:          @draft.last_name,
          email:             Customer.normalize_email(@draft.email),
          phone:             @draft.phone,
          group_name:        @draft.group_name,
          from_date:         @draft.arrival_date,
          to_date:           @draft.departure_date,
          adults:            [@draft.adults, 1].max,
          children:          @draft.children.to_i,
          status:            stay_status,
          payment_status:    "pending",
          platform:          "web",
          lodging_id:        @draft.lodging_id,
          price_cents:       price,
          shown_price_cents: price
        )
        booking.generate_token
        booking.save!
        @stay.stay_items.create!(bookable: booking)
      end
    end

    def existing_lodging_booking
      @stay.stay_items.where(bookable_type: "Booking").first&.bookable
    end

    # Réconcilie l'occupation d'ESPACES du séjour (epic #66, Phase 2) : rebuild
    # complet des `SpaceReservation` depuis le draft. Comme pour l'hébergement,
    # on NE TOUCHE PAS au `status`/`email` du SpaceBooking à l'édition (l'update
    # de statut déclenche l'email client — anti-spam admin).
    def reconcile_spaces!
      specs         = space_reservation_specs(@draft)
      space_booking = existing_space_booking(@stay)

      # Plus d'espace au draft → on détache/soft-delete un éventuel SpaceBooking.
      if specs.empty?
        if space_booking
          @stay.stay_items.where(bookable_type: "SpaceBooking").each { |i| i.soft_delete!(validate: false) }
          space_booking.soft_delete!(validate: false)
        end
        return
      end

      price = @draft.quote.spaces_cents
      dates = specs.map { |s| s[:date] }

      if space_booking
        space_booking.space_reservations.destroy_all
        space_booking.update!(
          firstname:   @draft.first_name,
          lastname:    @draft.last_name,
          phone:       @draft.phone,
          group_name:  @draft.group_name,
          from_date:   @draft.arrival_date || dates.min,
          to_date:     @draft.departure_date || dates.max,
          price_cents: price
        )
        specs.each do |spec|
          space_booking.space_reservations.create!(space: spec[:space], date: spec[:date], duration: spec[:duration])
        end
      else
        persist_space_booking!(
          stay:        @stay,
          draft:       @draft,
          specs:       specs,
          status:      @stay.status,
          price_cents: price
        )
      end
    end

    # Réconcilie le CAMPING du séjour (epic #66, Phase 3) : crée / met à jour /
    # détache le CampingBooking selon le draft. Comme pour l'hébergement, on ne
    # touche ni au token ni à l'email à l'édition.
    def reconcile_camping!
      camping = existing_camping_booking(@stay)

      unless draft_has_camping?(@draft)
        if camping
          @stay.stay_items.where(bookable_type: "CampingBooking").each { |i| i.soft_delete!(validate: false) }
          camping.soft_delete!(validate: false)
        end
        return
      end

      price = @draft.quote.camping_cents
      if camping
        camping.update!(
          firstname:   @draft.first_name,
          lastname:    @draft.last_name,
          phone:       @draft.phone,
          group_name:  @draft.group_name,
          from_date:   @draft.arrival_date,
          to_date:     @draft.departure_date,
          people:      [draft_camping_people(@draft), 1].max,
          price_cents: price
        )
      else
        persist_camping_booking!(stay: @stay, draft: @draft, status: @stay.status, price_cents: price)
      end
    end

    def reconcile_van!
      van = existing_van_booking(@stay)

      unless draft_has_van?(@draft)
        if van
          @stay.stay_items.where(bookable_type: "VanBooking").each { |i| i.soft_delete!(validate: false) }
          van.soft_delete!(validate: false)
        end
        return
      end

      price = @draft.quote.van_cents
      if van
        van.update!(
          firstname:   @draft.first_name,
          lastname:    @draft.last_name,
          phone:       @draft.phone,
          group_name:  @draft.group_name,
          from_date:   @draft.arrival_date,
          to_date:     @draft.departure_date,
          vehicles:    [draft_van_vehicles(@draft), 1].max,
          price_cents: price
        )
      else
        persist_van_booking!(stay: @stay, draft: @draft, status: @stay.status, price_cents: price)
      end
    end

    def reconcile_experiences!
      desired  = desired_experience_map
      allowed  = allowed_availability_ids

      @stay.experience_bookings.active.each do |eb|
        # On ne réconcilie (annule) QUE dans le périmètre de l'utilisateur.
        next unless allowed.include?(eb.experience_availability_id)
        next if desired.key?(eb.experience_availability_id)
        eb.update!(status: "cancelled")
      end

      desired.each do |availability_id, participants|
        eb = @stay.experience_bookings.active.find_by(experience_availability_id: availability_id)
        if eb
          eb.update!(participants: participants)
        else
          @stay.experience_bookings.create!(
            experience_availability_id: availability_id,
            participants: participants,
            status: "pending"
          )
        end
      end
    end

    def desired_experience_map
      allowed = allowed_availability_ids
      Array(@draft.experiences).each_with_object({}) do |entry, memo|
        aid          = entry[:availability_id].to_i
        participants = entry[:participants].to_i
        next if aid < 1 || participants < 1
        next unless allowed.include?(aid)
        memo[aid] = participants
      end
    end

    def allowed_availability_ids
      @allowed_availability_ids ||= ExperienceAvailability.for_user(@user).pluck(:id).to_set
    end

    def stay_status
      Stay::STATUSES_ADMIN_CREATABLE.include?(@requested_status) ? @requested_status : @stay.status
    end

    def raise_invalid(message)
      raise Invalid, message
    end
  end
end
