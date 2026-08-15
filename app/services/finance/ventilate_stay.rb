module Finance
  # Ventile un montant reçu sur les natures de recette d'un séjour (issue #185).
  #
  # **On ne re-cote jamais un vieux séjour.** Deux moteurs de prix ont coexisté
  # dans l'application et produisent des montants différents pour un même
  # séjour ; un devis reconstruit peut donc donner un total qui n'a jamais été
  # facturé. Le devis sert donc de PROPORTIONS, jamais de montant : les ratios
  # viennent de lui, la base est l'argent réellement reçu.
  #
  # Conséquence directe, et c'est elle qui rend le service sûr : la somme des
  # lignes vaut exactement le montant encaissé, quoi qu'ait pu devenir le
  # tarif entre-temps. Aucune ligne n'invente un euro.
  #
  # Ce fichier est le SEUL de `app/services/finance/` autorisé à toucher
  # `PricingModel` — l'anti-critère du lot le vérifie.
  class VentilateStay < ServiceBase
    class EmptyQuote < StandardError; end
    class MissingMapping < StandardError; end

    Line = Struct.new(:category, :label, :amount_cents, :general_account, :team, keyword_init: true)

    def initialize(stay:, amount_cents:)
      @stay = stay
      @amount_cents = amount_cents.to_i
    end

    def run
      catch_error(context: { stay: @stay.id }) { ventilate }
    end

    def run!
      ventilate
    end

    private

    def ventilate
      poids = weights
      if poids.values.sum <= 0
        raise EmptyQuote,
              "Le devis reconstruit du séjour ##{@stay.id} est vide : impossible d'en tirer une " \
              "ventilation. Affecte la ligne à la main."
      end

      categories = poids.keys
      parts = MoneyDistribution.distribute_cents(@amount_cents.abs, poids.values_at(*categories))

      categories.each_with_index.filter_map do |category, index|
        montant = parts[index]
        next if montant.zero?

        mapping = mappings[category]
        raise MissingMapping, "Aucun compte de recette pour la catégorie « #{category} »." if mapping.nil?

        Line.new(
          category: category,
          label: "#{RevenueMapping::CATEGORY_LABELS.fetch(category, category)} — séjour ##{@stay.id}",
          amount_cents: @amount_cents.negative? ? -montant : montant,
          general_account: mapping.general_account,
          team: mapping.team
        )
      end
    end

    # Les poids viennent du devis reconstruit, catégorie par catégorie. On ne
    # garde que celles qui portent quelque chose : une catégorie à zéro n'a pas
    # à produire une ligne vide au grand livre.
    def weights
      quote = PricingModel.quote(Stays::DraftReconstructor.call(@stay))

      # TOUTES les catégories du devis, sans exception. En omettre une ne perd
      # pas d'argent — c'est pire : sa part est redistribuée aux autres, et la
      # ventilation ment alors sur la NATURE de la recette. Une activité rangée
      # dans l'hébergement fausse le pilotage sans qu'aucun total ne bouge.
      {
        "lodging" => quote.lodging_only_cents.to_i,
        "spaces" => quote.spaces_cents.to_i,
        "camping" => quote.camping_cents.to_i,
        "van" => quote.van_cents.to_i,
        "meals" => quote.meals_cents.to_i,
        "terrace" => quote.terrace_cents.to_i,
        "hamac" => quote.hamac_cents.to_i,
        "experiences" => quote.experiences_cents.to_i
      }.reject { |_category, poids| poids.to_i <= 0 }
    end

    def mappings
      @mappings ||= RevenueMapping.includes(:general_account, :team).index_by(&:category)
    end
  end
end
