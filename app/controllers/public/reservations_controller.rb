module Public
  # Funnel B2C natif /reservation (PRD §3.1, Hotwire server-rendered).
  # Public : bypass Devise via Public::BaseController. FR-only (Q7).
  #
  # Étapes :
  #   1. start    — sélecteur « infos » vs « réserver » (AC-T2-02)
  #   2. compose  — dates + dispo + catalogue + options + repas + devis live
  #   3. quote    — recalcul Turbo Frame du panier sans full reload (AC-T2-10)
  #   4. contact  — coordonnées (champ chien obligatoire, AC-T2-09)
  #   5. create   — upsert Customer + Stay(pending) + Booking + Payment → Stripe
  #   6. confirmation / show via lien token
  class ReservationsController < Public::BaseController
    layout "public_sheet"

    DRAFT_SESSION_KEY = :reservation_draft

    before_action :load_draft, only: %i[compose quote advance_activities activities advance_contact contact create]
    skip_before_action :verify_authenticity_token, only: %i[advance_activities advance_contact]

    # Étape 1 — entrée, distinction info vs transaction.
    def start
    end

    HALL_SPACES = [
      { index: 0, kind: "grande_salle",  label: "Grande salle",            prices: "290 €/journée · 190 €/soirée · 350 €/journée+soirée" },
      { index: 1, kind: "petite_salle",  label: "Petite salle",            prices: "140 €/journée · 90 €/soirée · 170 €/journée+soirée" },
      { index: 2, kind: "cuisine_pro",   label: "Cuisine professionnelle", prices: "110 €/journée · 70 €/soirée · 140 €/journée+soirée" }
    ].freeze

    # Étape 2 — composition du séjour + devis temps-réel.
    def compose
      @lodgings = bookable_lodgings
      @hall_spaces = HALL_SPACES
      @quote = @draft.quote
    end

    # Transition compose → activités : persiste le draft, redirige vers l'étape activités.
    def advance_activities
      persist_draft(merged_draft_params)
      redirect_to public_reservation_activities_path
    end

    # Étape activités — sélection des expériences disponibles.
    def activities
      @experiences = bookable_experiences
      @quote = @draft.quote
    end

    # Transition activités → coordonnées : persiste les expériences choisies.
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
        meals: [:kind, :people], halls: [:kind, :days, :period],
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
      permitted[:halls] = Array(permitted[:halls]).reject { |row| row[:period].blank? }
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
  end
end
