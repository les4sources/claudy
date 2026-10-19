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
      # Un devis vide n'est pas une raison de bloquer (Michael, 2026-10-19 :
      # séjour #732, un hébergement sans logement ni chambre que le moteur ne
      # sait pas coter). Les prix ENREGISTRÉS sur la composition donnent les
      # mêmes proportions ; on ne refuse que s'ils sont vides eux aussi.
      poids = recorded_weights if poids.values.sum <= 0
      if poids.values.sum <= 0
        raise EmptyQuote,
              "Le devis reconstruit du séjour ##{@stay.id} est vide, et sa composition ne porte aucun prix : " \
              "impossible d'en tirer une ventilation. Affecte la ligne à la main."
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
          team: accueil || mapping.team
        )
      end
    end

    # Les poids viennent du devis reconstruit, catégorie par catégorie. On ne
    # garde que celles qui portent quelque chose : une catégorie à zéro n'a pas
    # à produire une ligne vide au grand livre.
    def weights
      quote = PricingModel.quote(Stays::DraftReconstructor.priced(@stay))

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

    # Le repli : les prix posés sur chaque élément du séjour, rangés dans les
    # mêmes catégories que le devis. Ce sont des montants de vente réels, donc
    # des proportions honnêtes ; la base reste l'argent reçu.
    def recorded_weights
      poids = Hash.new(0)
      @stay.stay_items.filter_map(&:bookable).each do |bookable|
        categorie = case bookable
                    when Booking then "lodging"
                    when SpaceBooking then "spaces"
                    when CampingBooking then bookable.kind == "terrasse" ? "terrace" : "camping"
                    when VanBooking then "van"
                    when HamacBooking then "hamac"
                    end
        poids[categorie] += bookable.try(:price_cents).to_i if categorie
      end
      poids["meals"] += @stay.meal_orders.active.sum(:price_cents).to_i
      poids["experiences"] += @stay.experience_bookings.active.sum { |activite| activite.price_cents.to_i }
      poids.reject { |_category, montant| montant <= 0 }
    end

    def mappings
      @mappings ||= RevenueMapping.includes(:general_account, :team).index_by(&:category)
    end

    # Un séjour est une affaire de l'Accueil (Michael, 2026-10-19) : c'est lui
    # qui loue les salles et les hébergements, donc TOUTES les lignes d'un
    # séjour vont sur son pôle, repas et activités compris. Le compte, lui,
    # garde la nature de la recette. Le pôle de `RevenueMapping` ne sert plus
    # que de repli, si aucun pôle Accueil n'existe.
    def accueil
      return @accueil if defined?(@accueil)

      @accueil = Team.accueil
    end
  end
end
