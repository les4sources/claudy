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
    # Reservations de chambres de l'hébergement (epic #66, Phase 6) : on réutilise
    # `build_reservations` + `get_rooms` du concern Bookable — SOURCE UNIQUE
    # partagée avec Bookings::CreateService — plutôt que de dupliquer la logique.
    # On n'appelle PAS `available?` du concern (le Builder fait sa propre
    # validation de dispo, avec force-dispo admin) ni `set_tier`/`set_price` (le
    # prix du Booking d'occupation est piloté par le devis, Phase 3 — intact).
    include Bookable

    class DraftInvalid < StandardError; end

    attr_reader :draft, :stay, :customer, :booking, :space_booking,
                :camping_booking, :van_booking, :payment, :availability_warning,
                :space_warning

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
    # `price_override_cents` / `platform` (epic #81, Phase 3) : prix libre imposé
    # et attribution OTA — RÉSERVÉS au canal admin. Ignorés hors `admin: true`,
    # même sur param forgé (le funnel public ne les expose jamais).
    def initialize(draft:, deposit_rate: Pricing::Catalog::DEFAULT_DEPOSIT_RATE,
                   admin: false, status: nil, source: nil, skip_availability: false,
                   price_override_cents: nil, platform: nil)
      @draft = draft
      @deposit_rate = deposit_rate
      @admin = admin
      @requested_status = status
      @requested_source = source
      @skip_availability = skip_availability
      @requested_price_override_cents = price_override_cents
      @requested_platform = platform
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
        # Occupation d'hébergement room-based (epic #66, Phase 6) : le Booking
        # `lodging_id` + dates NE SUFFIT PAS — sans Reservation par chambre le
        # séjour est invisible au calendrier (rendu par chambre, Phase 4) et le
        # veto `Lodging#available_between?` (qui compte les Reservation confirmées)
        # ne se pose jamais → surbooking silencieux. On crée donc les Reservation
        # dans TOUS les canaux (admin ET funnel public natif), aligné sur
        # `Bookings::CreateService`. Le veto reste piloté par le statut confirmed.
        build_lodging_reservations! if @booking
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
          # Prix imposé (epic #81, Phase 3) : persisté d'entrée. `total_amount_cents`
          # est réaligné juste après (voir plus bas) pour que le total reflète
          # l'override dès la création, sans attendre un recompute.
          price_override_cents: admin_price_override,
          notes: internal_notes
        )
        @stay.stay_items.create!(bookable: @booking) if @booking
        # Espaces (epic #66, Phase 2) : les salles / cuisine pro choisies
        # deviennent un SpaceBooking + StayItem, MÊME sans hébergement (séjour
        # « espaces seuls »). Sa part de prix vient du devis (`spaces_cents`) —
        # l'hébergement porte `lodging_bundle_cents`, donc aucun double-compte.
        @space_booking = build_space_booking_for!(@stay, quote)
        # Camping / van / repas (epic #66, Phase 3 ; alignement public issue #79) —
        # PERSISTÉS DANS TOUS LES CANAUX. Chacun devient son propre modèle et le
        # Booking d'hébergement porte `lodging_only_cents` (extraction SANS
        # double-compte, cf. `lodging_price_cents`). Ce n'est qu'une RE-VENTILATION :
        # le TOTAL du séjour et l'ACOMPTE restent identiques à avant (invariant #79),
        # car ils dérivent du devis (`quote`), inchangé par cette ventilation.
        @camping_booking = build_camping_booking_for!(@stay, quote)
        @van_booking     = build_van_booking_for!(@stay, quote)
        create_meal_orders!(@stay, draft)
        # Sélections d'activités du funnel (epic #55, Phase 4) : chaque créneau
        # choisi devient un ExperienceBooking `pending` rattaché au Stay — de la
        # MÊME nature que ceux du rail email, donc soumis à la validation porteur.
        # On réintègre leur montant au total prévu (mais JAMAIS à l'acompte).
        experiences_total = create_experience_bookings!(@stay)
        # Total du séjour : le prix imposé (epic #81) PRIME sur le devis. Sinon,
        # comportement historique — devis hors activités + activités créées.
        if admin_price_override.present?
          @stay.update!(total_amount_cents: admin_price_override)
        elsif experiences_total.positive?
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
      # Séjour activités-seules / repas-seuls SANS dates saisies (issue #80) :
      # dériver arrivée/départ de l'élément présent. `recompute_aggregates!`
      # redonne le MÊME total (bookables + activités actives + repas) — invariant
      # préservé — et ne touche pas aux dates s'il n'y a rien à dériver.
      @stay.recompute_aggregates! if @stay.arrival_date.blank? && @stay.bookables.empty?
      # Espaces DEVISÉS mais non persistables (aucune `Space` correspondante) :
      # on ne les perd pas en silence — le contrôleur admin remonte l'avertissement.
      @space_warning = unresolved_space_warning(draft)
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
      # Nuits requises UNIQUEMENT pour les réservables à la nuit (hébergement,
      # camping, van, hamac). Les compositions sans nuitée — location d'espace en
      # journée sèche (0 nuit), activités seules, repas seuls — sont légitimes
      # (issue #80) : elles portent leurs propres dates (espace/activité/repas).
      raise_invalid("Veuillez choisir des dates valides.") if requires_nights? && draft.nights < 1
      raise_invalid("Veuillez choisir un hébergement, un espace, une activité ou un repas.") unless bookable_content?
      raise_invalid("Veuillez indiquer si vous venez avec un animal (champ obligatoire).") if draft.dogs_count.nil?
      raise_invalid("Veuillez préciser votre prénom.") if draft.first_name.blank?
      raise_invalid("Veuillez préciser une adresse email valide.") unless Customer.exploitable_email?(draft.email)
      # Mode chambres seules (epic #81, Phase 5) : au moins une chambre doit être
      # cochée, sinon il n'y a rien à réserver (on ne retombe pas sur le gîte
      # entier en silence).
      if draft.lodging.present? && draft.rooms_mode? && draft.room_ids.blank?
        raise_invalid("Veuillez sélectionner au moins une chambre pour une réservation de chambres seules.")
      end
      # Revue Forge F1 : room_ids fournis mais tous étrangers au gîte (params
      # forgés) → sans ce garde-fou, Booking créé avec ZÉRO Reservation
      # (occupation fantôme, invisible du calendrier, aucun veto).
      if draft.lodging.present? && draft.rooms_mode? && draft.room_ids.present? &&
         draft.lodging.rooms.where(id: draft.room_ids).none?
        raise_invalid("Les chambres sélectionnées n'appartiennent pas à cet hébergement.")
      end
      if draft.lodging.present? && !lodging_available?
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

    # Dispo de l'hébergement : sur les chambres cochées en mode "rooms" (epic #81,
    # Phase 5), sur le gîte entier sinon. Source unique de vérité (veto Grand-Duc /
    # chambres partagées inclus).
    def lodging_available?
      if draft.rooms_mode?
        draft.lodging.rooms_available_between?(draft.room_ids, draft.arrival_date, draft.departure_date)
      else
        draft.lodging.available_between?(draft.arrival_date, draft.departure_date)
      end
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
        draft_has_spaces?(draft) ||
        draft.bookable_experiences? ||
        draft_has_meals?(draft)
    end

    # Réservables facturés À LA NUIT : ils exigent au moins une nuit. Les espaces
    # (forfait date+période), activités et repas n'en exigent pas (issue #80).
    def requires_nights?
      draft.lodging.present? || draft.campings.any? || draft.vans.any? || draft.hamacs.any?
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
        platform: booking_platform,
        lodging_id: draft.lodging_id,
        # Prix de l'occupation d'hébergement = hébergement PUR (`lodging_only_cents`),
        # dans TOUS les canaux (issue #79) : camping / van / repas sont extraits sur
        # leurs propres modèles. Invariant : Booking + SpaceBooking + CampingBooking
        # + VanBooking + MealOrder(s) + ExperienceBooking(s) == total du séjour.
        price_cents: lodging_price_cents(quote),
        shown_price_cents: lodging_price_cents(quote)
      )
      # booking_type (epic #66, Phase 6 ; chambres seules epic #81, Phase 5) :
      # attr_accessor NON persisté. En mode "rooms" l'occupation ne vise qu'un
      # sous-ensemble de chambres du gîte (cf. `reservation_rooms`) ; sinon le
      # gîte entier. On CONSERVE `lodging_id` dans les deux modes (contrairement
      # au canal Booking direct qui le retire) : le séjour garde ainsi la
      # référence du gîte (préremplissage édition, devis, entanglement).
      booking.booking_type = draft.rooms_mode? ? "rooms" : "lodging"
      booking.generate_token
      booking.save!
      booking
    end

    # Crée les Reservation {booking, room, date} de l'occupation d'hébergement :
    # une par chambre du lodging (`get_rooms` → `lodging.rooms`) et par nuit sur
    # [arrivée, départ) (`build_reservations`, concern Bookable). C'est ce qui rend
    # le séjour VISIBLE au calendrier (dès `pending`) et, une fois `confirmed`, pose
    # le veto de `Lodging#available_between?`. Aucune écriture de prix/tier ici :
    # l'invariant de prix (Phase 3) est préservé. Idempotent : no-op si le Booking
    # porte déjà des Reservation (rejeu de run! sur un booking déjà peuplé).
    def build_lodging_reservations!
      return if @booking.reservations.any?
      rooms = reservation_rooms
      return if rooms.blank?
      build_reservations(rooms)
      @booking.save!
    end

    # Chambres à réserver pour l'occupation d'hébergement. En mode "rooms" (epic
    # #81, Phase 5) : le SOUS-ENSEMBLE coché, borné aux chambres du gîte
    # (anti-injection cross-gîte). Sinon : toutes les chambres du gîte (== ce que
    # `get_rooms` renvoie en mode lodging — comportement historique inchangé).
    def reservation_rooms
      return Room.none if draft.lodging.blank?
      if draft.rooms_mode?
        draft.lodging.rooms.where(id: draft.room_ids)
      else
        draft.lodging.rooms
      end
    end

    # Part de prix portée par le Booking d'hébergement : hébergement PUR dans tous
    # les canaux (issue #79) — camping/van/repas vivent sur leurs propres modèles.
    def lodging_price_cents(quote)
      quote.lodging_only_cents
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

    # Prix imposé effectif : seulement en mode admin (jamais côté public, même sur
    # param forgé). nil = pas d'override → devis appliqué.
    def admin_price_override
      return nil unless @admin
      @requested_price_override_cents.presence
    end

    # Attribution OTA du Booking d'occupation (epic #81, Phase 3). Réservée à
    # l'admin ; le funnel public reste "web" (réservation directe native).
    def booking_platform
      return "web" unless @admin
      @requested_platform.presence || "web"
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
