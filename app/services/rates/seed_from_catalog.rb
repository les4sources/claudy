module Rates
  # Matérialise TOUTES les valeurs de `Pricing::Catalog` dans la table `rates`
  # (issue #124). Idempotent : relancer ne crée pas de doublon et n'écrase pas
  # un montant déjà édité par l'équipe — sauf en mode `force: true`.
  #
  # Le seed n'invente aucun prix : à l'issue d'un run, chaque clé porte
  # exactement le montant du catalogue, donc aucun devis ne change.
  class SeedFromCatalog
    Result = Struct.new(:created, :updated, :unchanged, :skipped, keyword_init: true) do
      def total = created + updated + unchanged + skipped

      def to_s
        "#{total} tarifs — #{created} créés, #{updated} mis à jour, " \
          "#{unchanged} inchangés, #{skipped} conservés (édités en base)"
      end
    end

    def initialize(force: false)
      @force = force
    end

    def run
      result = Result.new(created: 0, updated: 0, unchanged: 0, skipped: 0)

      entries.each do |entry|
        rate = Rate.find_by(key: entry[:key])

        if rate.nil?
          Rate.create!(entry)
          result.created += 1
        elsif rate.amount_cents == entry[:amount_cents]
          rate.update!(label: entry[:label], unit: entry[:unit])
          result.unchanged += 1
        elsif @force
          rate.update!(entry)
          result.updated += 1
        else
          result.skipped += 1
        end
      end

      Pricing::Rates.reset!
      result
    end

    # Toutes les entrées du catalogue, à plat.
    def entries
      lodging_entries + hall_entries + outdoor_entries + meal_entries + misc_entries
    end

    private

    def entry(key, amount_cents, label, unit: "cents")
      { key: key, amount_cents: amount_cents, label: label, unit: unit }
    end

    def lodging_entries
      Pricing::Catalog::LODGING_RATES.flat_map do |name, rate|
        slug = Pricing::Catalog.lodging_key(name)
        rows = [
          entry("lodging.#{slug}.first_night", rate.first_night_cents, "#{name} — première nuit"),
          entry("lodging.#{slug}.extra_night", rate.extra_night_cents, "#{name} — nuit suivante")
        ]
        rate.named_packages.each do |nights, package|
          rows << entry("lodging.#{slug}.package_#{nights}",
                        package[:amount_cents],
                        "#{name} — #{package[:label]} (#{nights} nuits)")
        end
        rows
      end
    end

    def hall_entries
      [[Pricing::Catalog::HALL_RATES, "hall", "semaine"],
       [Pricing::Catalog::HALL_RATES_WEEKEND, "hall_weekend", "week-end"]].flat_map do |table, prefix, period_label|
        table.flat_map do |kind, periods|
          periods.map do |period, amount|
            entry("#{prefix}.#{kind}.#{period}", amount,
                  "#{hall_label(kind)} — #{PERIOD_LABELS.fetch(period, period)} (#{period_label})")
          end
        end
      end
    end

    PERIOD_LABELS = {
      "journee"           => "journée",
      "soiree"            => "soirée",
      "journee_et_soiree" => "journée + soirée"
    }.freeze

    HALL_LABELS = {
      "grande_salle" => "Grande Salle",
      "petite_salle" => "Petite Salle",
      "cuisine_pro"  => "Cuisine professionnelle",
      "deux_salles"  => "Les 2 salles (duo)"
    }.freeze

    def hall_label(kind) = HALL_LABELS.fetch(kind, kind.to_s.tr("_", " ").capitalize)

    def outdoor_entries
      rows = Pricing::Catalog::CAMPING_PER_PERSON_NIGHT_CENTS.map do |kind, amount|
        entry("camping.#{kind}_per_person_night", amount, "Camping #{kind} — €/pers/nuit")
      end
      rows << entry("van.per_night", Pricing::Catalog::VAN_PER_NIGHT_CENTS,
                    "Van / camping-car — €/nuit")
      rows << entry("terrace.per_person_day", Pricing::Catalog::TERRACE_PER_PERSON_DAY_CENTS,
                    "Terrasse — €/pers/jour")
      Pricing::Catalog::HAMAC_FALLBACK_CENTS.each do |kind, amount|
        rows << entry("hamac.#{kind}", amount, "Hamac #{kind} — €/nuit/unité")
      end
      rows
    end

    def meal_entries
      rows = Pricing::Catalog::MEAL_PER_PERSON_CENTS.map do |kind, amount|
        entry("meal.#{kind}.per_person", amount, "#{meal_label(kind)} — €/pers")
      end
      rows << entry("pizza_party.base", Pricing::Catalog::PIZZA_PARTY_BASE_CENTS,
                    "Pizza Party — forfait allumage")
      rows << entry("pizza_party.per_person", Pricing::Catalog::PIZZA_PARTY_PER_PERSON_CENTS,
                    "Pizza Party — €/pers")
      rows
    end

    MEAL_LABELS = {
      "repas_vege_midi" => "Repas végétarien (midi)",
      "buffet"          => "Buffet pain-fromages"
    }.freeze

    def meal_label(kind) = MEAL_LABELS.fetch(kind, kind.to_s.tr("_", " ").capitalize)

    def misc_entries
      [
        entry("dog.supplement", Pricing::Catalog::DOG_SUPPLEMENT_CENTS,
              "Supplément chien — par séjour"),
        entry("deposit.default_rate",
              (Pricing::Catalog::DEFAULT_DEPOSIT_RATE * 100).round,
              "Acompte par défaut (% du total hors activités)",
              unit: "percent")
      ]
    end
  end
end
