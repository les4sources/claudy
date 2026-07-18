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
        reconcile_experiences!
        @stay.recompute_aggregates!
      end
      true
    end

    private

    def validate!
      raise_invalid("Veuillez choisir des dates valides.") if @draft.nights < 1
      # Phase 1 : un séjour admin porte au moins un hébergement (espaces / camping
      # arrivent aux phases 2-3). Retirer le DERNIER hébergement est donc hors
      # périmètre ici — on change ou on garde l'hébergement.
      raise_invalid("Veuillez sélectionner un hébergement.") if @draft.lodging.blank?
      unless Customer.exploitable_email?(@draft.email)
        raise_invalid("Veuillez préciser une adresse email valide pour le client.")
      end
      check_availability!
    end

    def check_availability!
      return if @draft.lodging.available_between?(@draft.arrival_date, @draft.departure_date)

      if @skip_availability
        @availability_warning =
          "Ces dates ne sont plus disponibles pour #{@draft.lodging.name} — " \
          "séjour enregistré en forçant la disponibilité (surbooking / saisie a posteriori)."
      else
        raise_invalid("Ces dates ne sont plus disponibles pour cet hébergement.")
      end
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
      price   = @draft.quote.total_excluding_experiences_cents
      booking = existing_lodging_booking

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
