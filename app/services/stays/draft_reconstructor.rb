module Stays
  # Reconstruit un `Reservations::Draft` COMPLET depuis un séjour persisté, pour
  # préremplir un formulaire (édition à l'identique, ou duplication après vidage
  # des dates par `Stays::DuplicateService`).
  #
  # Extrait du contrôleur (epic #81, Phase 7) pour éviter la duplication de code :
  # l'édition (dates conservées) et la duplication (dates vidées) partagent la
  # MÊME reconstruction de composition. La seule vérité recomposée ici est la
  # composition tarifable — jamais les paiements ni le prix imposé, absents du Draft.
  class DraftReconstructor
    def initialize(stay)
      @stay = stay
    end

    def self.call(stay)
      new(stay).to_draft
    end

    def to_draft
      booking = lodging_booking
      # Chambres seules (epic #81, Phase 5) : rétablit le mode + les chambres
      # cochées. La colonne `booking_type` fait foi ; dérivation des Reservation
      # en secours pour le legacy (cf. Booking#rooms_mode?).
      rooms_mode = booking&.rooms_mode?
      Reservations::Draft.new(
        lodging_id:     booking&.lodging_id,
        booking_type:   rooms_mode ? "rooms" : "lodging",
        room_ids:       rooms_mode ? booking.reservations.map(&:room_id).uniq : [],
        arrival_date:   @stay.arrival_date,
        departure_date: @stay.departure_date,
        arrival_time:   @stay.arrival_time.presence || space_booking&.arrival_time,
        departure_time: @stay.departure_time.presence || space_booking&.departure_time,
        # Grille par nuit (Michael 2026-07-20) : reconstituée depuis les N
        # CampingBooking / VanBooking (une plage par tranche contiguë) pour que
        # l'édition ré-affiche FIDÈLEMENT la grille du funnel. Présente → le Draft
        # dérive `campings`/`vans` d'elle ; absente (pas de dates / pas de plein
        # air) → repli sur les entrées pleine-fenêtre ci-dessous.
        per_night_resources: per_night_resources_from_stay,
        # Grille hébergement nuit par nuit du funnel public (`_stay_calendar`
        # lit `lodging_night_ids`, pas `lodging_id`) : sans elle, le formulaire
        # de modification client s'affichait vide (bug 2026-07-21).
        lodging_night_ids: lodging_night_ids_from_stay,
        adults:         booking&.adults,
        children:       booking&.children,
        group_name:     booking&.group_name,
        # Catégorie (Michael 2026-07-21) : reconstruite depuis le Stay pour que
        # l'édition admin ET la modification client (proposed_draft) la portent —
        # sinon une approbation de modif client l'effacerait. Vit sur le Stay,
        # PAS sur un bookable : source unique = `@stay.category`.
        category:       @stay.category,
        first_name:     @stay.customer&.first_name,
        last_name:      @stay.customer&.last_name,
        email:          @stay.customer&.email,
        phone:          @stay.customer&.phone,
        experiences:    @stay.experience_bookings.active.map { |eb|
          { id: eb.experience&.id, availability_id: eb.experience_availability_id, participants: eb.participants }
        },
        halls:          halls_from_stay,
        campings:       campings_from_stay,
        vans:           vans_from_stay,
        # Hamacs (issue #138) : repli pleine-fenêtre quand la grille n'est pas
        # dérivable (séjour sans dates). La grille, elle, est reconstruite dans
        # `per_night_resources_from_stay` — c'est elle qui fait foi si présente.
        hamacs:         hamacs_from_stay,
        meals:          meals_from_stay,
        terrasses:      terrasses_from_stay,
        # Précision libre du besoin d'espace (funnel public) : reconstruite depuis
        # la note interne préfixée du SpaceBooking, PRÉFIXE RETIRÉ, pour que le
        # textarea réaffiche le texte brut du client à l'édition / la modif client.
        spaces_note:    spaces_note_from_stay
      )
    end

    private

    # Reconstruit `per_night_resources = { "tente" => [...], "van" => [...] }` en
    # étalant chaque CampingBooking / VanBooking sur ses nuits `[from, to)`,
    # indexé depuis l'arrivée du séjour. nil si le séjour n'a pas de dates OU pas
    # de plein air — l'édition retombe alors sur les entrées pleine-fenêtre legacy.
    def per_night_resources_from_stay
      arrival   = @stay.arrival_date
      departure = @stay.departure_date
      return nil if arrival.blank? || departure.blank?
      nights = (departure - arrival).to_i
      return nil if nights < 1

      # Les TERRASSES (kind "terrasse") sont des CampingBooking mais N'ENTRENT PAS
      # dans la grille camping/van par nuit — elles ont leur propre reconstruction.
      campings = @stay.stay_items.select { |i| i.bookable_type == "CampingBooking" }
                      .filter_map(&:bookable).reject { |b| b.kind == "terrasse" }
      vans     = @stay.stay_items.select { |i| i.bookable_type == "VanBooking" }.filter_map(&:bookable)
      hamacs   = @stay.stay_items.select { |i| i.bookable_type == "HamacBooking" }.filter_map(&:bookable)
      return nil if campings.empty? && vans.empty? && hamacs.empty?

      pnr = {}
      pnr["tente"] = spread_nights(campings, arrival, nights, &:people)   if campings.any?
      pnr["van"]   = spread_nights(vans,     arrival, nights, &:vehicles) if vans.any?
      # Hamacs (issue #138) : une ligne de grille par TYPE, `hamac_simple` /
      # `hamac_double` — mêmes clés que celles postées par le funnel et le form
      # admin, donc le round-trip édition ré-affiche fidèlement la sélection.
      HamacBooking::KINDS.each do |kind|
        of_kind = hamacs.select { |h| h.kind.to_s == kind }
        next if of_kind.empty?
        pnr["hamac_#{kind}"] = spread_nights(of_kind, arrival, nights, &:count)
      end
      pnr
    end

    # Tableau de `nights` valeurs (0 par défaut), rempli par `yield(b)` sur chaque
    # nuit couverte par le réservable `b` (fenêtre `[from, to)`).
    def spread_nights(bookings, arrival, nights)
      arr = Array.new(nights, 0)
      bookings.each do |b|
        next if b.from_date.blank? || b.to_date.blank?
        (b.from_date...b.to_date).each do |date|
          idx = (date - arrival).to_i
          # Somme (revue Forge F2) : deux réservables du même type qui se
          # chevaucheraient une nuit (hors grille) ne s'écrasent pas en silence.
          arr[idx] += yield(b).to_i if idx >= 0 && idx < nights
        end
      end
      arr
    end

    # Une entrée par nuit du séjour `[arrivée, départ)` : l'id du Lodging occupé
    # cette nuit-là (fenêtre `[from, to)` de chaque Booking), nil sinon. nil
    # global si le séjour n'a ni dates ni hébergement.
    def lodging_night_ids_from_stay
      arrival   = @stay.arrival_date
      departure = @stay.departure_date
      return nil if arrival.blank? || departure.blank?
      nights = (departure - arrival).to_i
      return nil if nights < 1

      bookings = @stay.stay_items.select { |i| i.bookable_type == "Booking" }.filter_map(&:bookable)
      return nil if bookings.empty?

      arr = Array.new(nights, nil)
      bookings.each do |b|
        next if b.from_date.blank? || b.to_date.blank? || b.lodging_id.blank?
        (b.from_date...b.to_date).each do |date|
          idx = (date - arrival).to_i
          arr[idx] = b.lodging_id.to_s if idx >= 0 && idx < nights
        end
      end
      arr
    end

    def lodging_booking
      @stay.stay_items.where(bookable_type: "Booking").first&.bookable
    end

    def space_booking
      @stay.stay_items.where(bookable_type: "SpaceBooking").first&.bookable
    end

    # Note interne préfixée du SpaceBooking → texte brut du client (préfixe
    # retiré). nil si pas d'espace, note vide, ou note sans le préfixe « client »
    # (note d'équipe interne non issue du funnel — ne pas la ramener au textarea).
    def spaces_note_from_stay
      raw = space_booking&.notes
      return nil if raw.blank?
      prefix = SpaceComposition::SPACES_NOTE_PREFIX
      return nil unless raw.start_with?(prefix)
      raw.delete_prefix(prefix).presence
    end

    # Reconstruit l'entrée camping {kind, people, nights} depuis le CampingBooking
    # persisté (nights déduit de la fenêtre).
    def campings_from_stay
      camping = @stay.stay_items.where(bookable_type: "CampingBooking")
                     .filter_map(&:bookable).reject { |b| b.kind == "terrasse" }.first
      return [] if camping.nil?
      nights = camping.from_date && camping.to_date ? (camping.to_date - camping.from_date).to_i : @stay.experience_bookings.size
      [{ kind: camping.kind, people: camping.people, nights: [nights, 1].max }]
    end

    # Reconstruit les entrées van (une par véhicule) depuis le VanBooking persisté.
    def vans_from_stay
      van = @stay.stay_items.where(bookable_type: "VanBooking").first&.bookable
      return [] if van.nil?
      nights = van.from_date && van.to_date ? (van.to_date - van.from_date).to_i : 1
      Array.new([van.vehicles, 1].max) { { nights: [nights, 1].max } }
    end

    # Reconstruit les entrées hamac {kind, count, nights} depuis les HamacBooking
    # persistés (une par plage). Sert de repli quand la grille n'est pas
    # dérivable ; sinon le Draft dérive `hamacs` de `per_night_resources`.
    def hamacs_from_stay
      @stay.stay_items.select { |i| i.bookable_type == "HamacBooking" }
           .filter_map(&:bookable)
           .sort_by { |h| [h.kind.to_s, h.from_date.to_s] }
           .map do |h|
             nights = h.from_date && h.to_date ? (h.to_date - h.from_date).to_i : 1
             { kind: h.kind, count: h.count, nights: [nights, 1].max }
           end
    end

    # Reconstruit les terrasses {date, people} depuis les CampingBooking terrasse
    # (un par jour, `from_date` = jour d'occupation). Prérempli le fieldset admin.
    def terrasses_from_stay
      @stay.stay_items.select { |i| i.bookable_type == "CampingBooking" }
           .filter_map(&:bookable)
           .select { |b| b.kind == "terrasse" }
           .sort_by { |b| b.from_date.to_s }
           .map { |b| { date: b.from_date&.iso8601, people: b.people } }
    end

    # Reconstruit les repas {kind, date, people} depuis les MealOrder du séjour.
    def meals_from_stay
      @stay.meal_orders.map do |order|
        { kind: order.kind, date: order.date&.iso8601, people: order.people }
      end
    end

    # Reconstruit les lignes d'espaces {kind, date, period} depuis le SpaceBooking.
    # Le nom de la Space est re-mappé vers sa clé de pricing (grande_salle, …).
    def halls_from_stay
      sb = space_booking
      return [] if sb.nil?

      sb.space_reservations.map do |res|
        key = space_key_for(res.space)
        next if key.nil?
        # Durée canonique persistée ("day"…) → clé de PRICING ("journee"…),
        # sinon le devis d'édition ne retrouverait pas son tarif. Une valeur
        # historique déjà en vocabulaire pricing passe inchangée.
        period = SpaceComposition::PERIOD_BY_DURATION.fetch(res.duration.to_s, res.duration)
        { kind: key, date: res.date&.iso8601, period: period }
      end.compact
    end

    # `Space` → clé de pricing (inverse du mapping SpaceComposition). Résolution par
    # le `code` stable d'abord (issue #75), puis repli sur le nom d'affichage.
    def space_key_for(space)
      return nil if space.nil?

      by_code = SpaceComposition::SPACE_CODES_BY_KEY.find { |_key, code| code == space.code }&.first
      return by_code if by_code

      SpaceComposition::SPACE_NAMES_BY_KEY.find { |_key, names| names.include?(space.name) }&.first
    end
  end
end
