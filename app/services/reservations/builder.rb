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
    include SpaceComposition
    include CampingComposition
    include MealComposition

    class DraftInvalid < StandardError; end

    attr_reader :draft, :stay, :customer, :booking, :space_booking,
                :camping_booking, :van_booking, :payment, :availability_warning

    # Mode admin (epic #66, Phase 1) : le CRUD Séjour admin réutilise ce moteur
    # SANS jamais passer par Stripe. Les options `admin`/`status`/`source`/
    # `skip_availability` n'affectent QUE le canal admin ; le funnel public
    # (`admin: false`) garde exactement le comportement historique.
    #
    #   - admin: true           → ne crée AUCUN Payment (le solde se règle après,
    #                             via la page client /sejour/:token) ; c'est aussi
    #                             au contrôleur de NE PAS envoyer d'email client.
    #   - status:               → statut du Stay à la création (`pending`/`confirmed`),
    #                             au choix de l'admin. Défaut : `pending` (jamais
    #                             d'auto-confirm côté public — Q5/AC-T2-19).
    #   - source:               → canal d'attribution du Stay. Défaut `reservation`
    #                             (public) ; l'admin passe `manual`.
    #   - skip_availability:    → force la disponibilité : la dispo reste VÉRIFIÉE
    #                             (le veto Grand-Duc de `Lodging#available_between?`
    #                             fait foi) mais l'indisponibilité n'échoue plus —
    #                             elle est exposée via `availability_warning`
    #                             (surbooking / saisie a posteriori autorisés).
    def initialize(draft:, deposit_rate: Pricing::Catalog::DEFAULT_DEPOSIT_RATE,
                   admin: false, status: nil, source: nil, skip_availability: false)
      @draft = draft
      @deposit_rate = deposit_rate
      @admin = admin
      @requested_status = status
      @requested_source = source
      @skip_availability = skip_availability
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
          source: stay_source,
          status: stay_status,
          arrival_date: draft.arrival_date,
          departure_date: draft.departure_date,
          total_amount_cents: quote.total_excluding_experiences_cents,
          notes: internal_notes
        )
        @stay.stay_items.create!(bookable: @booking) if @booking
        # Espaces (epic #66, Phase 2) : les salles / cuisine pro choisies
        # deviennent un SpaceBooking + StayItem, MÊME sans hébergement (séjour
        # « espaces seuls »). Sa part de prix vient du devis (`spaces_cents`) —
        # l'hébergement porte `lodging_bundle_cents`, donc aucun double-compte.
        @space_booking = build_space_booking_for!(@stay, quote)
        # Camping / van / repas (epic #66, Phase 3) — PERSISTÉS UNIQUEMENT côté
        # admin. Le funnel public reste devis-only pour ces éléments (leur montant
        # est noyé dans `lodging_bundle_cents` du Booking, comportement historique
        # inchangé). Côté admin, chacun devient son propre modèle et le Booking
        # d'hébergement porte `lodging_only_cents` (extraction sans double-compte).
        if @admin
          @camping_booking = build_camping_booking_for!(@stay, quote)
          @van_booking     = build_van_booking_for!(@stay, quote)
          create_meal_orders!(@stay, draft)
        end
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
        #
        # Canal admin (epic #66) : AUCUN paiement n'est créé à l'enregistrement —
        # le solde se règle après coup depuis la page client /sejour/:token.
        @payment = build_payment!(quote) unless @admin
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
        # Force-dispo admin (epic #66) : on n'échoue pas, on consigne un
        # avertissement que le contrôleur remonte à l'admin. Hors force, le
        # comportement historique tient (l'indisponibilité bloque la création).
        if @skip_availability
          @availability_warning =
            "Ces dates ne sont plus disponibles pour #{draft.lodging.name} — " \
            "séjour enregistré en forçant la disponibilité (surbooking / saisie a posteriori)."
        else
          raise_invalid("Ces dates ne sont plus disponibles pour cet hébergement.")
        end
      end
      check_space_availability!
      check_outdoor_capacity!
    end

    # Camping / van : capacité GLOBALE du domaine (epic #66, Phase 3). Vérifiée
    # UNIQUEMENT côté admin — le funnel public ne persiste pas ces réservables et
    # garde son comportement historique. Même logique de force que l'hébergement.
    def check_outdoor_capacity!
      return unless @admin
      messages = [camping_capacity_message(draft), van_capacity_message(draft)].compact
      return if messages.empty?

      if @skip_availability
        forced = messages.map { |m| "#{m} — séjour enregistré en forçant la disponibilité." }
        @availability_warning = [@availability_warning, *forced].compact.join(" ")
      else
        raise_invalid(messages.join(" "))
      end
    end

    # Dispo espaces CAPACITY-AWARE (`Space#available_on?`, source unique). Hors
    # force, un espace déjà plein bloque ; en force-dispo admin, on consigne un
    # avertissement (surbooking / saisie a posteriori) sans échouer — comme pour
    # l'hébergement.
    def check_space_availability!
      conflicts = space_availability_conflicts(space_reservation_specs(draft))
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

    def bookable_content?
      draft.lodging.present? ||
        draft.campings.any? ||
        draft.vans.any? ||
        draft.hamacs.any? ||
        draft_has_spaces?(draft)
    end

    # Crée le SpaceBooking (+ StayItem) du séjour depuis les espaces du draft.
    # No-op si aucun espace résolu. La dispo capacity-aware a déjà été vérifiée
    # (ou forcée) dans `validate_draft!`. Retourne le SpaceBooking ou nil.
    def build_space_booking_for!(stay, quote)
      specs = space_reservation_specs(draft)
      return nil if specs.empty?

      persist_space_booking!(
        stay:        stay,
        draft:       draft,
        specs:       specs,
        status:      stay_status,
        price_cents: quote.spaces_cents
      )
    end

    # Camping (epic #66, Phase 3) : no-op si aucune personne demandée. Sa part de
    # prix vient du devis (`camping_cents`). Retourne le CampingBooking ou nil.
    def build_camping_booking_for!(stay, quote)
      return nil unless draft_has_camping?(draft)

      persist_camping_booking!(
        stay:        stay,
        draft:       draft,
        status:      stay_status,
        price_cents: quote.camping_cents
      )
    end

    def build_van_booking_for!(stay, quote)
      return nil unless draft_has_van?(draft)

      persist_van_booking!(
        stay:        stay,
        draft:       draft,
        status:      stay_status,
        price_cents: quote.van_cents
      )
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
        status: stay_status,
        payment_status: "pending",
        platform: "web",
        lodging_id: draft.lodging_id,
        # Prix de l'occupation d'hébergement (epic #66, Phase 3) :
        #   - Canal ADMIN → `lodging_only_cents` : hébergement PUR (camping / van /
        #     repas sont extraits sur leurs propres modèles). Invariant admin :
        #     Booking + SpaceBooking + CampingBooking + VanBooking + MealOrder(s)
        #     + ExperienceBooking(s) == total du séjour.
        #   - Canal PUBLIC → `lodging_bundle_cents` : comportement historique
        #     INCHANGÉ (camping / van / repas noyés dans le Booking, devis-only).
        price_cents: lodging_price_cents(quote),
        shown_price_cents: lodging_price_cents(quote)
      )
      booking.generate_token
      booking.save!
      booking
    end

    # Part de prix portée par le Booking d'hébergement selon le canal (voir
    # `build_booking!`). Admin : hébergement pur ; public : bundle historique.
    def lodging_price_cents(quote)
      @admin ? quote.lodging_only_cents : quote.lodging_bundle_cents
    end

    def build_payment!(quote)
      Payment.create!(
        booking: @booking,
        stay: @stay,
        amount_cents: quote.deposit_cents,
        status: "pending",
        payment_method: "card"
      )
    end

    # Statut du Stay (et du Booking d'occupation) à la création. Le public reste
    # sur `pending` (jamais d'auto-confirm — Q5) ; l'admin choisit explicitement.
    def stay_status
      return "pending" unless @admin
      Stay::STATUSES_ADMIN_CREATABLE.include?(@requested_status) ? @requested_status : "pending"
    end

    def stay_source
      @requested_source.presence || "reservation"
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
