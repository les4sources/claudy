module Reservations
  # Commit d'un Draft /reservation en données persistées (B2C natif, Q5).
  #
  # Crée, dans une transaction :
  #   - un Customer upserté par email lowercase (logique tranche 1, AC-T2-18) ;
  #   - un Stay `source: "reservation"`, `status: "pending"` — JAMAIS auto-confirm
  #     (Q5 / AC-T2-19) : la confirmation reste une action manuelle de Malau ;
  #   - un Booking porteur du contact + du prix (item du Stay via StayItem) qui
  #     réutilise toute l'infra Stripe/webhook de la tranche 1 (AC-T2-20) ;
  #   - un Payment `pending` du montant de l'acompte (50 % par défaut), dont l'id
  #     sert de client_reference_id à Stripe Checkout.
  #
  # Le supplément chien est plafonné à un seul chien (Q2) : un draft avec
  # plusieurs chiens est marqué pour traitement manuel (note interne) et ne
  # facture jamais N × 50 € (AC-T2-09b / AC-T2-15).
  class Builder < ServiceBase
    class DraftInvalid < StandardError; end

    attr_reader :draft, :stay, :customer, :booking, :payment

    def initialize(draft:, deposit_rate: Pricing::Catalog::DEFAULT_DEPOSIT_RATE)
      @draft = draft
      @deposit_rate = deposit_rate
      @report_errors = true
    end

    def run
      run!
      true
    rescue DraftInvalid => e
      set_error_message(e.message)
      false
    rescue => e
      Sentry.capture_exception(e)
      set_error_message("Une erreur est survenue lors de l'enregistrement de votre réservation.")
      false
    end

    def run!
      validate_draft!
      quote = draft.quote(deposit_rate: @deposit_rate)

      ActiveRecord::Base.transaction do
        @customer = upsert_customer!
        @booking = build_booking!(quote)
        @stay = Stay.create!(
          customer: @customer,
          source: "reservation",
          status: "pending",
          arrival_date: draft.arrival_date,
          departure_date: draft.departure_date,
          total_amount_cents: quote.total_cents,
          notes: internal_notes
        )
        @stay.stay_items.create!(bookable: @booking)
        @payment = Payment.create!(
          booking: @booking,
          amount_cents: quote.deposit_cents,
          status: "pending",
          payment_method: "card"
        )
      end
      true
    end

    # Devis courant (source unique UI + email — AC-T2-17).
    def quote
      @quote ||= draft.quote(deposit_rate: @deposit_rate)
    end

    def multi_dogs?
      draft.dogs_count.to_i > 1
    end

    private

    def validate_draft!
      raise_invalid("Veuillez choisir un hébergement et des dates valides.") if draft.lodging.nil? || draft.nights < 1
      raise_invalid("Veuillez indiquer si vous venez avec un animal (champ obligatoire).") if draft.dogs_count.nil?
      raise_invalid("Veuillez préciser votre prénom.") if draft.first_name.blank?
      raise_invalid("Veuillez préciser une adresse email valide.") unless Customer.exploitable_email?(draft.email)
      unless draft.lodging.available_between?(draft.arrival_date, draft.departure_date)
        raise_invalid("Ces dates ne sont plus disponibles pour cet hébergement.")
      end
    end

    def upsert_customer!
      email = Customer.normalize_email(draft.email)
      customer = Customer.where(email: email).first_or_initialize
      customer.email = email # défensif : garantit l'email même si first_or_initialize ne le porte pas
      customer.first_name = draft.first_name if customer.first_name.blank?
      customer.last_name = draft.last_name if customer.last_name.blank?
      customer.phone = draft.phone if customer.phone.blank?
      customer.save!
      customer
    end

    def build_booking!(quote)
      booking = Booking.new(
        firstname: draft.first_name,
        lastname: draft.last_name,
        email: Customer.normalize_email(draft.email),
        phone: draft.phone,
        group_name: draft.group_name,
        from_date: draft.arrival_date,
        to_date: draft.departure_date,
        adults: [draft.adults, 1].max,
        children: draft.children.to_i,
        status: "pending",
        payment_status: "pending",
        platform: "web",
        lodging_id: draft.lodging_id,
        price_cents: quote.total_cents,
        shown_price_cents: quote.total_cents
      )
      booking.generate_token
      booking.save!
      booking
    end

    # Multi-chiens hors flow auto (Q2) : on consigne pour traitement manuel.
    def internal_notes
      return if draft.dogs_count.to_i <= 1
      "⚠️ Demande multi-chiens (#{draft.dogs_count}) — supplément chien plafonné à 1 dans le flow auto, à traiter manuellement avec le client."
    end

    def raise_invalid(message)
      raise DraftInvalid, message
    end
  end
end
