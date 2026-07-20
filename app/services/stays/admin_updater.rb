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

    attr_reader :stay, :availability_warning, :space_warning

    # `price_override_cents` / `platform` / `source` (epic #81, Phase 3) : prix
    # imposé, attribution OTA du Booking et canal du Stay. `price_override_cents`
    # est appliqué TEL QUEL — nil le RETIRE (retour au devis B2C). Ce service est
    # le canal admin exclusif : aucun garde-fou public à prévoir ici.
    def initialize(stay:, draft:, status: nil, skip_availability: false, user: nil,
                   price_override_cents: nil, platform: nil, source: nil)
      @stay = stay
      @draft = draft
      @requested_status = status
      @skip_availability = skip_availability
      @user = user
      @requested_price_override_cents = price_override_cents
      @requested_platform = platform
      @requested_source = source
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
        # `price_override_cents` est posé AVANT le recompute final : ce dernier
        # honore l'override (total = override) tout en gardant les dates dérivées
        # de la composition. nil retire l'override → le recompute reprend le devis.
        @stay.update!(
          customer:             upsert_customer!,
          status:               stay_status,
          source:               stay_source,
          price_override_cents: @requested_price_override_cents.presence
        )
        reconcile_lodging!
        reconcile_spaces!
        reconcile_camping!
        reconcile_van!
        reconcile_meals!(@stay, @draft)
        reconcile_experiences!
        @stay.recompute_aggregates!
      end
      # Espaces DEVISÉS mais non persistables (aucune `Space` correspondante) :
      # remontés à l'admin plutôt que perdus en silence (issue #75).
      @space_warning = unresolved_space_warning(@draft)
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
      # Chambres seules (epic #81, Phase 5) : au moins une chambre cochée.
      if @draft.lodging.present? && @draft.rooms_mode? && @draft.room_ids.blank?
        raise_invalid("Veuillez sélectionner au moins une chambre pour une réservation de chambres seules.")
      end
      # Revue Forge F1 : chambres toutes étrangères au gîte = params forgés,
      # jamais une saisie UI — refus explicite plutôt qu'occupation fantôme.
      if @draft.lodging.present? && @draft.rooms_mode? && @draft.room_ids.present? &&
         @draft.lodging.rooms.where(id: @draft.room_ids).none?
        raise_invalid("Les chambres sélectionnées n'appartiennent pas à cet hébergement.")
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
      return if lodging_available?

      if @skip_availability
        @availability_warning =
          "Ces dates ne sont plus disponibles pour #{@draft.lodging.name} — " \
          "séjour enregistré en forçant la disponibilité (surbooking / saisie a posteriori)."
      else
        raise_invalid("Ces dates ne sont plus disponibles pour cet hébergement.")
      end
    end

    # Dispo de l'hébergement à l'édition. Mode gîte entier : `available_between?`
    # (comportement historique inchangé). Mode chambres seules (epic #81, Phase 5) :
    # dispo des chambres cochées, en EXCLUANT la propre occupation du séjour édité
    # (sinon un séjour confirmé se bloquerait lui-même à chaque réenregistrement).
    # Dispo en édition, mode gîte entier comme chambres seules : on vérifie les
    # Reservation confirmées sur les chambres visées en EXCLUANT TOUS les
    # Booking du séjour édité (revue Forge F4 : `.first` seul laissait un
    # éventuel second Booking auto-bloquer le séjour ; et le mode gîte entier
    # ne s'excluait pas du tout — un séjour confirmé se bloquait lui-même).
    def lodging_available?
      if @draft.rooms_mode?
        ids = @draft.lodging.rooms.where(id: @draft.room_ids).pluck(:id)
        # Chambres toutes hors gîte : déjà refusé en validation ; réponse
        # conservatrice si on arrive ici par un autre chemin.
        return false if ids.empty?
      else
        ids = @draft.lodging.rooms.pluck(:id)
        # Gîte sans chambre modélisée : aucune Reservation possible — seule une
        # indisponibilité posée à la main compte (comportement historique).
        if ids.empty?
          return @draft.lodging.unavailabilities
                       .where(date: @draft.arrival_date..@draft.departure_date).none?
        end
      end

      # Contrat de dates (issue #94) : `[arrival_date, departure_date)` est une
      # fenêtre de séjour ; le jour de départ n'est PAS occupé. Les `Reservation`
      # sont NUITÉES → on borne aux nuits `arrival_date..(departure_date-1)` (borne
      # haute excluant le jour de départ) pour ne pas refuser une rotation dos-à-dos.
      # Le `max` garde un intervalle valide même sur une fenêtre dégénérée (0 nuit).
      last_night = [@draft.departure_date - 1, @draft.arrival_date].max
      scope = Reservation.joins(:booking)
                         .where(date: @draft.arrival_date..last_night,
                                room_id: ids, bookings: { status: "confirmed" })
      own_ids = @stay.stay_items.where(bookable_type: "Booking").pluck(:bookable_id)
      scope = scope.where.not(bookings: { id: own_ids }) if own_ids.any?
      # Les `Unavailability` gardent leur sémantique de JOURNÉES PLEINES (inclusif
      # du jour de départ) — volontairement différente des nuits ci-dessus.
      scope.none? &&
        @draft.lodging.unavailabilities.where(date: @draft.arrival_date..@draft.departure_date).none?
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
        # `platform` (attribution OTA, epic #81) est en revanche propagé : son
        # changement ne déclenche AUCUN email (cf. `notify_customer_on_update`).
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
          platform:          booking_platform(booking.platform),
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
          platform:          booking_platform,
          lodging_id:        @draft.lodging_id,
          price_cents:       price,
          shown_price_cents: price
        )
        booking.generate_token
        booking.save!
        @stay.stay_items.create!(bookable: booking)
      end

      # Reconstruction PROPRE des Reservation de chambres (epic #81, Phase 5). Le
      # changement d'hébergement, de dates OU de chambres cochées doit se refléter
      # dans les Reservation qui portent l'occupation (calendrier + veto de dispo).
      # On les rebâtit intégralement pour rester la source de vérité : gîte entier
      # → toutes les chambres du gîte ; chambres seules → le sous-ensemble coché.
      rebuild_reservations!(booking)
    end

    # Rebâtit les Reservation {room, date} de l'occupation depuis le draft courant.
    # Idempotent : détruit d'abord l'existant, puis reconstruit sur [arrivée, départ).
    def rebuild_reservations!(booking)
      booking.reservations.destroy_all
      rooms = reservation_rooms
      return if rooms.blank?
      rooms.each do |room|
        (booking.from_date..(booking.to_date - 1.day)).each do |date|
          booking.reservations.create!(room: room, date: date)
        end
      end
    end

    # Chambres de l'occupation : sous-ensemble coché (mode rooms, borné au gîte) ou
    # toutes les chambres du gîte (mode lodging). Miroir de `Reservations::Builder`.
    def reservation_rooms
      return Room.none if @draft.lodging.blank?
      if @draft.rooms_mode?
        @draft.lodging.rooms.where(id: @draft.room_ids)
      else
        @draft.lodging.rooms
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
        space_booking.assign_attributes(
          firstname:   @draft.first_name,
          lastname:    @draft.last_name,
          phone:       @draft.phone,
          group_name:  @draft.group_name,
          from_date:   @draft.arrival_date || dates.min,
          to_date:     @draft.departure_date || dates.max,
          price_cents: price
        )
        # Facturation espace (epic #81, Phase 6) : appliquée seulement si le draft
        # la porte ; sinon les valeurs existantes survivent. N'affecte ni le
        # `status` ni l'`email` → aucun email déclenché (cf. en-tête de classe).
        assign_space_billing(space_booking, @draft)
        space_booking.save!
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

    # Canal du Stay : on ne change la source QUE si l'admin en fournit une valide
    # (`SOURCES`). Sinon on préserve celle d'origine — ne jamais écraser en
    # silence l'attribution d'un séjour issu d'un canal automatique.
    def stay_source
      Stay::SOURCES.include?(@requested_source) ? @requested_source : @stay.source
    end

    # Attribution OTA à propager au Booking. Priorité au choix admin ; à défaut,
    # on préserve la valeur courante (`current`) plutôt que de la réinitialiser.
    def booking_platform(current = nil)
      @requested_platform.presence || current || "web"
    end

    def raise_invalid(message)
      raise Invalid, message
    end
  end
end
