module Rates
  # Matérialise les clés du barème « Sourciers » (issue #156) : bar, épicerie,
  # repas partagés, cagnotte, dôme, animaux. Elles ne sont encore consommées par
  # personne — le catalogue de produits (phase 3) et les charges récurrentes
  # (phase 5) viendront les lire.
  #
  # Idempotent au sens fort : une clé déjà présente n'est JAMAIS réécrite, ni son
  # montant ni sa version. Rejouer la tâche après une édition dans Paramètres >
  # Tarifs ne défait donc rien.
  #
  # `pot.swing_share` est la seule à naître avec une fin de validité : les 5 €
  # destinés à Magali pour la balançoire s'arrêtent le 30 avril 2027. Cette date
  # vit en base, pas dans le code — la prolonger, c'est éditer un champ.
  class SeedSourciers
    ENTRIES = [
      { key: "bar.member_markup", amount_cents: 110, unit: "percent",
        label: "Bar — coefficient sourcier (% du prix d'achat)" },
      { key: "grocery.member_ratio", amount_cents: 95, unit: "percent",
        label: "Épicerie — coefficient sourcier (% du prix de référence)" },
      { key: "grocery.public_ratio", amount_cents: 105, unit: "percent",
        label: "Épicerie — coefficient public (% du prix de référence)" },
      { key: "meal.batchcooking.per_person", amount_cents: 500,
        label: "Batch cooking — €/pers" },
      { key: "meal.collective.per_person", amount_cents: 650,
        label: "Repas collectif — €/pers" },
      { key: "meal.batchcooking.cook_volunteering", amount_cents: 350,
        label: "Batch cooking — €/pers pour la personne qui cuisine" },
      { key: "pot.monthly_per_adult", amount_cents: 1_000,
        label: "Cagnotte — €/adulte/mois" },
      { key: "pot.swing_share", amount_cents: 500,
        label: "Cagnotte — part balançoire (jusqu'au 30 avril 2027)",
        active_until: Date.new(2027, 4, 30) },
      { key: "dome.monthly_flat", amount_cents: 5_000,
        label: "Dôme — forfait mensuel" },
      { key: "dome.daily", amount_cents: 1_000,
        label: "Dôme — à la journée" },
      { key: "pet.balthazar_monthly", amount_cents: 3_000,
        label: "Balthazar — forfait mensuel" }
    ].freeze

    Result = Struct.new(:created, :existing, :versions_created, keyword_init: true) do
      def to_s
        "#{created} clé(s) créée(s), #{existing} déjà présente(s), " \
          "#{versions_created} version(s) initiale(s) créée(s)"
      end
    end

    def run
      result = Result.new(created: 0, existing: 0, versions_created: 0)

      ENTRIES.each do |entry|
        rate = Rate.find_by(key: entry[:key])

        if rate
          result.existing += 1
        else
          rate = create_rate(entry)
          result.created += 1
        end

        next if rate.rate_versions.exists?

        # Le montant versionné est celui du tarif, pas celui de la constante :
        # une clé éditée par l'équipe garde sa valeur.
        rate.rate_versions.create!(
          amount_cents: rate.amount_cents,
          active_from: RateVersion::ORIGIN,
          active_until: entry[:active_until]
        )
        result.versions_created += 1
      end

      Pricing::Rates.reset!
      result
    end

    private

    def create_rate(entry)
      Rate.create!(
        key: entry[:key],
        amount_cents: entry[:amount_cents],
        label: entry[:label],
        unit: entry.fetch(:unit, "cents")
      )
    end
  end
end
