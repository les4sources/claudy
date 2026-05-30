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
  def lodging_lines
    lodging = read(:lodging)
    nights = read(:nights).to_i
    return [] if lodging.nil? || nights < 1

    rate = Pricing::Catalog.lodging_rate(lodging.name)
    return [] if rate.nil?

    quote = rate.quote_for(nights)
    [Line.new(label: quote[:label], amount_cents: quote[:amount_cents])]
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

  # --- Salles : forfait/jour ---
  def hall_lines
    Array(read(:halls)).filter_map do |entry|
      unit = Pricing::Catalog::HALL_PER_DAY_CENTS[entry[:kind].to_s]
      next if unit.nil?
      days = [entry[:days].to_i, 1].max
      Line.new(label: "#{humanize(entry[:kind])} — #{days} jour(s)",
               amount_cents: unit * days)
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
