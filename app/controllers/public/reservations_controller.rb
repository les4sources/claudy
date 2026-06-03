module Public
  # Funnel B2C natif /reservation — 3 étapes (tranche 2).
  #   1. dates     — dates du séjour + groupe + animal
  #   2. compose   — composition : hébergement, espaces, camping, hamacs
  #   3. contact   — coordonnées client → commit + Stripe
  class ReservationsController < Public::BaseController
    layout "public_sheet"

    DRAFT_SESSION_KEY = :reservation_draft
    HALL_SLOT_COUNT   = 6

    before_action :load_draft, only: %i[dates advance_dates compose quote advance_contact activities contact create]
    skip_before_action :verify_authenticity_token, only: %i[advance_contact]

    def start
      redirect_to public_reservation_dates_path
    end

    # Étape 1 — dates, groupe, animal.
    def dates
    end

    # Transition étape 1 → 2.
    def advance_dates
      persist_draft(merged_draft_params)
      redirect_to public_reservation_compose_path
    end

    HALL_KIND_TO_SPACE = {
      "grande_salle" => "Grande Salle",
      "petite_salle" => "Petite Salle",
      "cuisine_pro"  => "Cuisine professionnelle"
    }.freeze

    # Étape 2 — composition du séjour + devis temps-réel.
    def compose
      @lodgings              = bookable_lodgings
      @quote                 = @draft.quote
      @cal_month             = Date.today.beginning_of_month
      @availability_calendar = build_availability_calendar(@lodgings, month: @cal_month)
    end

    # Étape activités (accès via email token — pas dans le funnel direct).
    def activities
      @experiences = bookable_experiences
      @quote = @draft.quote
    end

    # Transition étape 2 → 3 (advance depuis le Stimulus quote controller).
    def advance_contact
      persist_draft(merged_draft_params)
      redirect_to public_reservation_contact_path
    end

    # Recalcul du panier (Turbo Frame, sans rechargement complet — AC-T2-10).
    def quote
      persist_draft(merged_draft_params)
      @lodgings = bookable_lodgings
      @quote = @draft.quote
      respond_to do |format|
        format.turbo_stream { render :quote }
        format.html { redirect_to public_reservation_compose_path }
      end
    end

    # Étape 3 — coordonnées client.
    def contact
      persist_draft(merged_draft_params)
      @quote = @draft.quote
    end

    # Étape finale — commit + redirection Stripe Checkout.
    def create
      persist_draft(merged_draft_params)
      builder = Reservations::Builder.new(draft: @draft)
      if builder.run
        ReservationMailer.confirmation_request(builder.stay).deliver_later
        pay = Payments::PayService.new(payment_id: builder.payment.id)
        clear_draft
        if pay.run
          redirect_to pay.checkout_session_url, allow_other_host: true, data: { turbo: false }
        else
          redirect_to public_booking_path(builder.booking.token),
                      notice: "Votre demande est enregistrée. Nous vous recontactons pour le paiement."
        end
      else
        @lodgings = bookable_lodgings
        @quote = @draft.quote
        flash.now[:alert] = builder.error_message(default: "Votre réservation n'a pas pu être enregistrée.")
        render :contact, status: :unprocessable_entity
      end
    end

    # Turbo Frame navigation pour le calendrier de disponibilités (1 mois par page).
    def availability_calendar
      today_month = Date.today.beginning_of_month
      max_month   = today_month >> 18
      parsed      = params[:month] ? (Date.parse("#{params[:month]}-01") rescue today_month) : today_month
      @cal_month  = [[parsed, today_month].max, max_month].min.beginning_of_month
      @lodgings   = bookable_lodgings
      @availability_calendar = build_availability_calendar(@lodgings, month: @cal_month)
      render layout: false
    end

    private

    def load_draft
      @draft = Reservations::Draft.new(session[DRAFT_SESSION_KEY] || {})
    end

    def persist_draft(attrs)
      incoming = attrs.to_h.deep_symbolize_keys
      merged = @draft.to_h.merge(incoming) do |_key, old, new|
        new.nil? || (new.respond_to?(:empty?) && new.empty? && !old.nil?) ? old : new
      end
      @draft = Reservations::Draft.new(merged)
      session[DRAFT_SESSION_KEY] = @draft.to_h
      @draft
    end

    def clear_draft
      session.delete(DRAFT_SESSION_KEY)
    end

    def merged_draft_params
      permitted = params.fetch(:reservation, {}).permit(
        :lodging_id, :arrival_date, :departure_date, :dogs_count,
        :adults, :children, :first_name, :last_name, :email, :phone, :group_name,
        meals: [:kind, :people], halls: [:kind, :date, :period],
        campings: [:kind, :people, :nights], vans: [:nights],
        pizza_parties: [:people], hamacs: [:kind, :count],
        experiences: [:id, :participants]
      ).to_h
      %i[meals halls campings vans pizza_parties hamacs experiences].each do |key|
        next unless permitted[key].is_a?(Hash)
        permitted[key] = permitted[key].values
      end
      %i[meals campings vans pizza_parties hamacs].each do |key|
        permitted[key] = Array(permitted[key]).reject { |row| row.values.all?(&:blank?) }
      end
      permitted[:halls] = Array(permitted[:halls]).reject { |row| row[:kind].blank? || row[:date].blank? || row[:period].blank? }
      permitted[:experiences] = Array(permitted[:experiences]).select { |r| r[:participants].to_i > 0 }
      permitted
    end

    def bookable_experiences
      Experience.where(deleted_at: nil).where.not(name: "Pizza Party").order(:name)
    end

    def bookable_lodgings
      names = ["La Hulotte", "La Chevêche", "Le Grand-Duc"]
      Lodging.where(name: names).sort_by { |l| names.index(l.name) || 99 }
    end

    # Construit les données pour le Gantt calendrier des disponibilités (1 mois).
    def build_availability_calendar(lodgings, month: nil)
      month   = (month || Date.today).beginning_of_month
      start   = month
      finish  = month.end_of_month
      dates   = (start..finish).to_a

      lodging_rows = lodgings.map do |lodging|
        reserved = Reservation.includes(:booking)
          .where(date: start..finish, room: lodging.rooms.pluck(:id), booking: { status: "confirmed" })
          .pluck(:date).to_set
        unavail = lodging.unavailabilities.where(date: start..finish).pluck(:date).to_set
        { name: lodging.name, occupied: reserved | unavail }
      end

      hall_rows = HALL_KIND_TO_SPACE.filter_map do |_kind, space_name|
        space = Space.find_by(name: space_name)
        next unless space
        booked = SpaceReservation.includes(:space_booking)
          .where(date: start..finish, space: space, space_booking: { status: "confirmed" })
          .pluck(:date).to_set
        { name: space_name, occupied: booked }
      end

      { dates: dates, lodging_rows: lodging_rows, hall_rows: hall_rows }
    end
  end
end
