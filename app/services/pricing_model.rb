# Moteur de pricing de la tranche 2 (PRD §3.2, Q2/Q3, AC-T2-12 → AC-T2-17).
#
# Service pur, sans table : prend un `stay_draft` (objet répondant au contrat
# ci-dessous) et retourne un devis structuré — breakdown ligne par ligne TVAC,
# total et acompte. Le même breakdown alimente l'UI temps-réel ET le récap email
# (source unique, AC-T2-17).
#
# Tous les montants sont en cents et TVAC ("pas de TVA en plus").
#
# Contrat de stay_draft (duck-typed — peut être un PORO, un Struct ou un Stay) :
#   - #lodging        => Lodging | nil (porte un name canonique)
#   - #nights         => Integer (nb de nuits)
#   - #dogs_count     => Integer (nb de chiens demandés ; plafonné à 1 en flow auto)
#   - #campings       => [ { kind: "tente"|"hamac", people: Integer, nights: Integer }, ... ]
#   - #vans           => [ { nights: Integer }, ... ] (ou Integer count via #vans_count)
#   - #halls          => [ { kind: "grande_salle"|..., days: Integer }, ... ]
#   - #meals          => [ { kind: "repas_vege_midi"|..., people: Integer }, ... ]
#   - #pizza_parties  => [ { people: Integer }, ... ]
# Toute méthode absente est traitée comme vide / zéro — le draft minimal n'a
# besoin que de #lodging + #nights.
class PricingModel
  # `category` (epic #55, Phase 1) tague la nature de la ligne (ex : `:experience`)
  # pour permettre au devis d'isoler les activités du reste. `to_h` reste
  # INCHANGÉ ({label:, amount_cents:}) — l'UI et l'email le consomment tel quel.
  Line = Struct.new(:label, :amount_cents, :category, keyword_init: true) do
    def to_h
      { label: label, amount_cents: amount_cents }
    end
  end

  # `experiences_cents` (epic #55, Phase 1) : part des activités dans le total.
  # `total_cents` reste le total COMPLET (activités comprises) pour l'affichage
  # funnel ; `total_excluding_experiences_cents` en retire les activités —
  # c'est cette base qui pilote l'acompte et le montant persisté du Stay tant
  # que les activités ne sont pas encore réservées (phases suivantes).
  Quote = Struct.new(:lines, :total_cents, :deposit_cents, :deposit_rate,
                     :experiences_cents, keyword_init: true) do
    def total_excluding_experiences_cents
      total_cents.to_i - experiences_cents.to_i
    end

    # Part des ESPACES (salles / cuisine pro) dans le total (epic #66, Phase 2).
    # Permet de ventiler proprement le devis entre le `Booking` d'hébergement et
    # le `SpaceBooking` d'espaces SANS jamais double-compter : l'hébergement porte
    # `lodging_bundle_cents`, les espaces `spaces_cents`, la somme reste
    # `total_excluding_experiences_cents`.
    def spaces_cents
      category_cents(:space)
    end

    # Parts camping / van / repas (epic #66, Phase 3). Chacune est extraite du
    # devis pour être portée par son propre modèle persisté (`CampingBooking`,
    # `VanBooking`, `MealOrder`) côté canal admin — sans jamais double-compter.
    def camping_cents = category_cents(:camping)
    def van_cents     = category_cents(:van)
    def meals_cents   = category_cents(:meal)
    # Terrasse (ADMIN uniquement, décision Michael 2026-07-20) : part datée à la
    # journée, portée par des `CampingBooking` de `kind: "terrasse"`.
    def terrace_cents = category_cents(:terrace)
    # Hamacs (issue #138) : part extraite du devis pour être portée par les
    # `HamacBooking` persistés — dans TOUS les canaux, comme camping/van.
    def hamac_cents   = category_cents(:hamac)

    # Base hébergement/camping/repas = total hors activités ET hors espaces.
    # INCHANGÉ pour préserver EXACTEMENT le canal public (funnel) : côté public,
    # camping/van/repas restent devis-only et noyés dans le prix du `Booking`.
    def lodging_bundle_cents
      total_excluding_experiences_cents - spaces_cents
    end

    # Hébergement PUR (epic #66, Phase 3) = bundle MOINS camping/van/repas. C'est
    # la part que porte le `Booking` d'hébergement dans le canal ADMIN, où
    # camping/van/repas vivent sur leurs propres modèles. Invariant admin :
    #   lodging_only + spaces + camping + van + meals == total_excluding_experiences.
    def lodging_only_cents
      lodging_bundle_cents - camping_cents - van_cents - meals_cents - terrace_cents - hamac_cents
    end

    def category_cents(category)
      lines.select { |line| line.category == category }.sum(&:amount_cents)
    end

    def breakdown
      lines.map(&:to_h)
    end

    def to_h
      { lines: breakdown,
        total_cents: total_cents,
        deposit_cents: deposit_cents,
        deposit_rate: deposit_rate }
    end
  end

  # API publique (AC-T2-12). Retourne un Quote.
  def self.quote(stay_draft, deposit_rate: Pricing::Catalog.default_deposit_rate)
    new(stay_draft, deposit_rate: deposit_rate).quote
  end

  def initialize(stay_draft, deposit_rate: Pricing::Catalog.default_deposit_rate)
    @draft = stay_draft
    @deposit_rate = deposit_rate
  end

  def quote
    lines = []
    lines.concat(lodging_lines)
    lines.concat(camping_lines)
    lines.concat(van_lines)
    lines.concat(hamac_lines)
    lines.concat(experience_lines)
    lines.concat(space_lines)
    lines.concat(meal_lines)
    lines.concat(terrace_lines)
    lines.concat(pizza_party_lines)
    lines.concat(dog_lines)

    total = lines.sum(&:amount_cents)
    # Les activités sont exclues de l'assiette de l'acompte (epic #55, Phase 1) :
    # on ne demande pas d'acompte sur des activités pas encore confirmées par
    # l'équipe. L'acompte porte donc sur le total HORS activités.
    experiences = lines.select { |line| line.category == :experience }.sum(&:amount_cents)
    deposit = ((total - experiences) * @deposit_rate).round

    Quote.new(lines: lines, total_cents: total,
              experiences_cents: experiences,
              deposit_cents: deposit, deposit_rate: @deposit_rate)
  end

  private

  # --- Hébergement : formule fermée dégressive + forfait nommé override (Q3) ---
  # Supporte le multi-hébergement via lodging_night_ids (Array indexé par nuit).
  # Fallback sur lodging + nights si lodging_night_ids absent (backward compat).
  def lodging_lines
    # Chambres seules (epic #81, Phase 5) : le barème B2C (`LODGING_RATES`) est un
    # FORFAIT par gîte entier — il n'existe pas de tarif par chambre exploitable.
    # En mode "rooms", on ne facture donc AUCUN forfait d'hébergement automatique ;
    # le total du séjour vient du Prix total imposé (override, Phase 3). L'UI
    # l'annonce explicitement dans le panneau devis.
    return [] if read(:rooms_mode?)

    night_ids = Array(read(:lodging_night_ids)).map { |id| id.presence }

    if night_ids.any?(&:present?)
      nights_by_id = Hash.new(0)
      night_ids.each { |id| nights_by_id[id] += 1 if id }
      nights_by_id.filter_map do |lodging_id, night_count|
        lodging = Lodging.find_by(id: lodging_id)
        next unless lodging
        rate = Pricing::Catalog.lodging_rate(lodging.name)
        next unless rate
        q = rate.quote_for(night_count)
        Line.new(label: q[:label], amount_cents: q[:amount_cents])
      end
    else
      lodging = read(:lodging)
      nights  = read(:nights).to_i
      return [] if lodging.nil? || nights < 1
      rate = Pricing::Catalog.lodging_rate(lodging.name)
      return [] if rate.nil?
      q = rate.quote_for(nights)
      [Line.new(label: q[:label], amount_cents: q[:amount_cents])]
    end
  end

  # --- Camping / bivouac : €/pers/nuit ---
  def camping_lines
    Array(read(:campings)).filter_map do |entry|
      unit = Pricing::Catalog.camping_per_person_night_cents(entry[:kind])
      next if unit.nil?
      people = entry[:people].to_i
      nights = entry[:nights].to_i
      next if people < 1 || nights < 1
      Line.new(label: "Camping #{entry[:kind]} — #{people} pers × #{nights} nuit(s)",
               amount_cents: unit * people * nights, category: :camping)
    end
  end

  # --- Van / camping-car : forfait/nuit/véhicule ---
  def van_lines
    vans = Array(read(:vans))
    if vans.empty? && read(:vans_count).to_i.positive?
      vans = Array.new(read(:vans_count).to_i) { { nights: read(:nights).to_i } }
    end
    vans.filter_map do |entry|
      nights = entry[:nights].to_i
      next if nights < 1
      Line.new(label: "Van / camping-car — #{nights} nuit(s)",
               amount_cents: Pricing::Catalog.van_per_night_cents * nights, category: :van)
    end
  end

  # --- Salles & cuisine pro : forfait par ligne {kind, date, period} ---
  PERIOD_LABELS = {
    "journee"           => "journée",
    "soiree"            => "soirée",
    "journee_et_soiree" => "journée + soirée"
  }.freeze

  SPACE_NAMES = {
    "grande_salle" => "Grande Salle",
    "petite_salle" => "Petite Salle",
    "cuisine_pro"  => "Cuisine professionnelle"
  }.freeze

  # --- Espaces (salles / cuisine pro) : lignes ponctuelles `halls` + grille
  # nuit-par-nuit `space_slots`, avec REMISE DUO (décision Michael 2026-07-20).
  #
  # Les deux représentations produisent d'abord des ENTRÉES normalisées
  # ({key, date, period, weekend, position_label, label, amount_cents}), puis un
  # passage de combinaison remplace chaque paire Grande + Petite salle du MÊME
  # jour et de la MÊME période par une seule ligne « Les 2 salles (duo) » au tarif
  # duo (< somme). Périodes différentes le même jour → pas de duo, somme normale.
  # Vaut au funnel public comme en admin (même moteur, décision figée).
  DUO_KEYS = %w[grande_salle petite_salle].freeze

  def space_lines
    combine_duo(hall_space_entries + slot_space_entries)
  end

  # Entrées ponctuelles `halls` ({kind, date, period}). Tarif SEMAINE (comme
  # historiquement — pas de logique week-end sur ce canal ponctuel).
  def hall_space_entries
    Array(read(:halls)).filter_map do |entry|
      key = entry[:kind].to_s
      next unless Pricing::Catalog.hall_kind?(key)
      period = entry[:period].to_s
      unit   = Pricing::Catalog.hall_rate_cents(key, period)
      next if unit.nil?
      date = parse_space_date(entry[:date])
      date_label = date&.strftime("%-d/%m")
      next if date_label.nil?
      period_label = PERIOD_LABELS[period] || period
      { key: key, date: date, period: period, weekend: false,
        position_label: date_label,
        label: "#{humanize(key)} — #{date_label}, #{period_label}",
        amount_cents: unit }
    end
  end

  # Entrées grille nuit-par-nuit `space_slots` : tarif semaine ou week-end selon
  # la date. ven (wday=5) et sam (wday=6) → tarifs week-end ; autres → semaine.
  def slot_space_entries
    slots = read(:space_slots)
    return [] if slots.blank?

    arrival   = read(:arrival_date)
    departure = read(:departure_date)
    stay_dates = (arrival && departure) ? (arrival...departure).to_a : []

    slots.flat_map do |space_key, periods|
      key = space_key.to_s
      next [] unless Pricing::Catalog.hall_kind?(key)
      space_name = SPACE_NAMES[key] || key

      Array(periods).each_with_index.filter_map do |period, night_idx|
        next if period.blank?
        p       = period.to_s
        date    = stay_dates[night_idx]
        weekend = !!(date && [5, 6].include?(date.wday))
        unit    = Pricing::Catalog.hall_rate_cents(key, p, weekend: weekend)
        next if unit.nil?
        period_label = PERIOD_LABELS[p] || p
        { key: key, date: date, period: p, weekend: weekend,
          position_label: "nuit #{night_idx + 1}",
          label: "#{space_name} — nuit #{night_idx + 1}, #{period_label}",
          amount_cents: unit }
      end
    end.compact
  end

  # Combine les entrées d'espaces : chaque paire Grande + Petite salle sur le
  # MÊME (date, période) → une ligne duo. Le reste passe inchangé. On apparie au
  # plus UNE grande avec UNE petite par groupe (un éventuel doublon reste séparé).
  def combine_duo(entries)
    duo_groups = entries
      .select { |e| e[:date] && DUO_KEYS.include?(e[:key]) }
      .group_by { |e| [e[:date], e[:period]] }
      .select { |_, es| es.map { |e| e[:key] }.uniq.sort == DUO_KEYS.sort }

    # Le duo n'emprunte le tarif week-end que si les DEUX salles étaient
    # week-end (cas propre de la grille un ven/sam) ; sinon tarif semaine.
    group_weekend = duo_groups.transform_values { |es| es.all? { |e| e[:weekend] } }

    consumed = Hash.new { |h, k| h[k] = { "grande_salle" => false, "petite_salle" => false } }
    emitted  = {}

    entries.filter_map do |e|
      gid = [e[:date], e[:period]]
      if e[:date] && DUO_KEYS.include?(e[:key]) && duo_groups.key?(gid) && !consumed[gid][e[:key]]
        consumed[gid][e[:key]] = true
        next nil if emitted[gid]
        emitted[gid] = true
        duo_line(e, group_weekend[gid])
      else
        Line.new(label: e[:label], amount_cents: e[:amount_cents], category: :space)
      end
    end
  end

  def duo_line(entry, weekend)
    unit = Pricing::Catalog.hall_rate_cents("deux_salles", entry[:period], weekend: weekend)
    period_label = PERIOD_LABELS[entry[:period]] || entry[:period]
    Line.new(label: "Les 2 salles (duo) — #{entry[:position_label]}, #{period_label}",
             amount_cents: unit, category: :space)
  end

  def parse_space_date(value)
    return value if value.is_a?(Date)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # --- Repas : €/pers ---
  def meal_lines
    Array(read(:meals)).filter_map do |entry|
      unit = Pricing::Catalog.meal_per_person_cents(entry[:kind])
      next if unit.nil?
      people = entry[:people].to_i
      next if people < 1
      Line.new(label: "#{humanize(entry[:kind])} — #{people} pers",
               amount_cents: unit * people, category: :meal)
    end
  end

  # --- Terrasse : forfait €/pers/JOUR, une ligne par jour d'occupation ---
  # ADMIN uniquement (décision Michael 2026-07-20). Chaque entrée `{date, people}`
  # devient une ligne `category: :terrace`. Le funnel public ne porte jamais cette
  # clé (non permise dans le contrôleur public) → aucune ligne côté public.
  def terrace_lines
    Array(read(:terrasses)).filter_map do |entry|
      entry  = entry.symbolize_keys if entry.respond_to?(:symbolize_keys)
      people = entry[:people].to_i
      next if people < 1
      date_label = begin
        Date.parse(entry[:date].to_s).strftime("%-d/%m")
      rescue ArgumentError, TypeError
        nil
      end
      label = date_label ? "Terrasse — #{date_label}, #{people} pers" : "Terrasse — #{people} pers"
      Line.new(label: label,
               amount_cents: Pricing::Catalog.terrace_per_person_day_cents * people,
               category: :terrace)
    end
  end

  # --- Hamacs (RentalItem, mai-octobre) : forfait/nuit/unité ---
  # entry[:nights] override le total du séjour pour les entrées per-nuit (backward compat).
  def hamac_lines
    stay_nights = read(:nights).to_i
    Array(read(:hamacs)).filter_map do |entry|
      count = entry[:count].to_i
      next if count < 1
      nights = (entry[:nights] || stay_nights).to_i
      next if nights < 1
      rate = Pricing::Catalog.hamac_rate(entry[:kind])
      next if rate.nil?
      label = entry[:kind].to_s == "double" ? "Hamac double" : "Hamac simple"
      Line.new(label: "#{label} × #{count} — #{nights} nuit(s)",
               amount_cents: rate * count * nights, category: :hamac)
    end
  end

  # --- Expériences (Experience) : forfait fixe + €/pers ---
  # Le calcul vit dans `Pricing::ExperienceLine` (source de vérité unique,
  # epic #55). Les lignes sont taguées `category: :experience` pour que le
  # devis puisse les isoler de l'assiette de l'acompte.
  def experience_lines
    Array(read(:experiences)).filter_map do |entry|
      exp = Experience.find_by(id: entry[:id])
      next if exp.nil?
      participants = entry[:participants].to_i
      next if participants < 1
      amount = Pricing::ExperienceLine.amount_cents(exp, participants: participants)
      next if amount < 1
      label_parts = [exp.name, "#{participants} pers"]
      Line.new(label: label_parts.join(" — "), amount_cents: amount, category: :experience)
    end
  end

  # --- Pizza Party : forfait + €/pers ---
  def pizza_party_lines
    Array(read(:pizza_parties)).filter_map do |entry|
      people = entry[:people].to_i
      amount = Pricing::Catalog.pizza_party_base_cents +
               Pricing::Catalog.pizza_party_per_person_cents * people
      Line.new(label: "Pizza Party — allumage + #{people} pers",
               amount_cents: amount)
    end
  end

  # --- Supplément chien : 50 €/séjour, plafonné à UN chien en flow auto (Q2) ---
  def dog_lines
    dogs = read(:dogs_count).to_i
    return [] if dogs < 1
    # Le flow auto ne facture qu'un seul chien, quel que soit le nombre demandé
    # (multi-chiens = hors flow, traité manuellement par Malau — AC-T2-09b/15).
    [Line.new(label: "Supplément chien", amount_cents: Pricing::Catalog.dog_supplement_cents)]
  end

  def read(method)
    @draft.respond_to?(method) ? @draft.public_send(method) : nil
  end

  def humanize(key)
    key.to_s.tr("_", " ").capitalize
  end
end
