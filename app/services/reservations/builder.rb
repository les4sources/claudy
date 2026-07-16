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
        # Stay-first (epic #26, Phase 2) : le Booking n'est plus l'ancre de
        # paiement, c'est une OCCUPATION d'hébergement — il bloque le calendrier
        # via lodging_id + dates. Un séjour sans hébergement (camping, espaces)
        # n'en crée donc plus : le « Booking fantôme » disparaît.
        @booking = draft.lodging.present? ? build_booking!(quote) : nil
        # Assiette de l'acompte (epic #55, Phase 1) : l'acompte EXCLUT toujours
        # les activités — on ne demande pas d'avance sur des créneaux pas encore
        # validés par le porteur (Phase 2). Le TOTAL PRÉVU du Stay, lui, agrège
        # l'hébergement/espaces + les activités `pending` créées ci-dessous
        # (sémantique `total_amount_cents` du modèle Stay). Le solde des activités
        # partira au paiement du solde (Phase 3), une fois le porteur validé.
        @stay = Stay.create!(
          customer: @customer,
          source: "reservation",
          status: "pending",
          arrival_date: draft.arrival_date,
          departure_date: draft.departure_date,
          total_amount_cents: quote.total_excluding_experiences_cents,
          notes: internal_notes
        )
        @stay.stay_items.create!(bookable: @booking) if @booking
        # Sélections d'activités du funnel (epic #55, Phase 4) : chaque créneau
        # choisi devient un ExperienceBooking `pending` rattaché au Stay — de la
        # MÊME nature que ceux du rail email, donc soumis à la validation porteur.
        # On réintègre leur montant au total prévu (mais JAMAIS à l'acompte).
        experiences_total = create_experience_bookings!(@stay)
        if experiences_total.positive?
          @stay.update!(total_amount_cents: quote.total_excluding_experiences_cents + experiences_total)
        end
        # Le paiement est rattaché au Stay dans tous les cas ; le booking n'est
        # plus qu'une référence de commodité pour le canal historique. Son montant
        # reste l'acompte HORS activités (`quote.deposit_cents`).
        @payment = Payment.create!(
          booking: @booking,
          stay: @stay,
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

    # Un séjour doit porter des dates valides et AU MOINS un élément réservé —
    # mais plus forcément un hébergement (epic #26, Phase 2) : un séjour camping
    # ou espaces seuls est légitime, et c'est justement lui qui ne doit plus
    # produire de Booking fantôme.
    def validate_draft!
      raise_invalid("Veuillez choisir des dates valides.") if draft.nights < 1
      raise_invalid("Veuillez choisir un hébergement ou un emplacement.") unless bookable_content?
      raise_invalid("Veuillez indiquer si vous venez avec un animal (champ obligatoire).") if draft.dogs_count.nil?
      raise_invalid("Veuillez préciser votre prénom.") if draft.first_name.blank?
      raise_invalid("Veuillez préciser une adresse email valide.") unless Customer.exploitable_email?(draft.email)
      if draft.lodging.present? && !draft.lodging.available_between?(draft.arrival_date, draft.departure_date)
        raise_invalid("Ces dates ne sont plus disponibles pour cet hébergement.")
      end
    end

    def bookable_content?
      draft.lodging.present? ||
        draft.campings.any? ||
        draft.vans.any? ||
        draft.hamacs.any? ||
        Array(draft.halls).any? ||
        Array(draft.space_slots).any?
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

    # Persiste les sélections de créneau du draft (epic #55, Phase 4) en
    # `ExperienceBooking` `pending`, dans la transaction courante. Chaque entrée
    # porte `availability_id` = `ExperienceAvailability` (créneau daté, NOT NULL)
    # et `participants`. Les entrées sans créneau (ancienne forme
    # `experiences: [{id, participants}]`, rétrocompat / pricing) sont ignorées :
    # un ExperienceBooking exige un créneau. Retourne la somme des montants TVAC
    # des activités créées, pour réintégration au total prévu du Stay.
    def create_experience_bookings!(stay)
      Array(draft.experiences).sum(0) do |entry|
        avail_id     = entry[:availability_id].presence
        participants = entry[:participants].to_i
        next 0 if avail_id.blank? || participants < 1

        booking = ExperienceBooking.create!(
          stay_id: stay.id,
          experience_availability_id: avail_id,
          participants: participants,
          status: "pending"
        )
        booking.price_cents
      end
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
        # Occupation d'hébergement : son prix suit le total HORS activités
        # (fix montant fantôme, epic #55 Phase 1) — cohérent avec le
        # `total_amount_cents` du Stay et l'assiette de l'acompte.
        price_cents: quote.total_excluding_experiences_cents,
        shown_price_cents: quote.total_excluding_experiences_cents
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
