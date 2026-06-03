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
  Line = Struct.new(:label, :amount_cents, keyword_init: true) do
    def to_h
      { label: label, amount_cents: amount_cents }
    end
  end

  Quote = Struct.new(:lines, :total_cents, :deposit_cents, :deposit_rate, keyword_init: true) do
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
  def self.quote(stay_draft, deposit_rate: Pricing::Catalog::DEFAULT_DEPOSIT_RATE)
    new(stay_draft, deposit_rate: deposit_rate).quote
  end

  def initialize(stay_draft, deposit_rate: Pricing::Catalog::DEFAULT_DEPOSIT_RATE)
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
    lines.concat(hall_lines)
    lines.concat(meal_lines)
    lines.concat(pizza_party_lines)
    lines.concat(dog_lines)

    total = lines.sum(&:amount_cents)
    deposit = (total * @deposit_rate).round

    Quote.new(lines: lines, total_cents: total,
              deposit_cents: deposit, deposit_rate: @deposit_rate)
  end

  private

  # --- Hébergement : formule fermée dégressive + forfait nommé override (Q3) ---
  # Supporte le multi-hébergement via lodging_night_ids (Array indexé par nuit).
  # Fallback sur lodging + nights si lodging_night_ids absent (backward compat).
  def lodging_lines
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
      unit = Pricing::Catalog::CAMPING_PER_PERSON_NIGHT_CENTS[entry[:kind].to_s]
      next if unit.nil?
      people = entry[:people].to_i
      nights = entry[:nights].to_i
      next if people < 1 || nights < 1
      Line.new(label: "Camping #{entry[:kind]} — #{people} pers × #{nights} nuit(s)",
               amount_cents: unit * people * nights)
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
               amount_cents: Pricing::Catalog::VAN_PER_NIGHT_CENTS * nights)
    end
  end

  # --- Salles & cuisine pro : forfait par ligne {kind, date, period} ---
  PERIOD_LABELS = {
    "journee"           => "journée",
    "soiree"            => "soirée",
    "journee_et_soiree" => "journée + soirée"
  }.freeze

  def hall_lines
    Array(read(:halls)).filter_map do |entry|
      rates = Pricing::Catalog::HALL_RATES[entry[:kind].to_s]
      next if rates.nil?
      period = entry[:period].to_s
      unit = rates[period]
      next if unit.nil?
      date_label = begin
        Date.parse(entry[:date].to_s).strftime("%-d/%m")
      rescue ArgumentError, TypeError
        nil
      end
      next if date_label.nil?
      period_label = PERIOD_LABELS[period] || period
      Line.new(label: "#{humanize(entry[:kind])} — #{date_label}, #{period_label}",
               amount_cents: unit)
    end
  end

  # --- Repas : €/pers ---
  def meal_lines
    Array(read(:meals)).filter_map do |entry|
      unit = Pricing::Catalog::MEAL_PER_PERSON_CENTS[entry[:kind].to_s]
      next if unit.nil?
      people = entry[:people].to_i
      next if people < 1
      Line.new(label: "#{humanize(entry[:kind])} — #{people} pers",
               amount_cents: unit * people)
    end
  end

  # --- Hamacs (RentalItem, mai-octobre) : forfait/nuit/unité ---
  def hamac_lines
    nights = read(:nights).to_i
    return [] if nights < 1
    Array(read(:hamacs)).filter_map do |entry|
      count = entry[:count].to_i
      next if count < 1
      rate = Pricing::Catalog.hamac_rate(entry[:kind])
      next if rate.nil?
      label = entry[:kind].to_s == "double" ? "Hamac double" : "Hamac simple"
      Line.new(label: "#{label} × #{count} — #{nights} nuit(s)",
               amount_cents: rate * count * nights)
    end
  end

  # --- Expériences (Experience) : forfait fixe + €/pers ---
  def experience_lines
    Array(read(:experiences)).filter_map do |entry|
      exp = Experience.find_by(id: entry[:id])
      next if exp.nil?
      participants = entry[:participants].to_i
      next if participants < 1
      amount = exp.fixed_price_cents.to_i + exp.price_cents.to_i * participants
      next if amount < 1
      label_parts = [exp.name, "#{participants} pers"]
      Line.new(label: label_parts.join(" — "), amount_cents: amount)
    end
  end

  # --- Pizza Party : forfait + €/pers ---
  def pizza_party_lines
    Array(read(:pizza_parties)).filter_map do |entry|
      people = entry[:people].to_i
      amount = Pricing::Catalog::PIZZA_PARTY_BASE_CENTS +
               Pricing::Catalog::PIZZA_PARTY_PER_PERSON_CENTS * people
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
    [Line.new(label: "Supplément chien", amount_cents: Pricing::Catalog::DOG_SUPPLEMENT_CENTS)]
  end

  def read(method)
    @draft.respond_to?(method) ? @draft.public_send(method) : nil
  end

  def humanize(key)
    key.to_s.tr("_", " ").capitalize
  end
end
