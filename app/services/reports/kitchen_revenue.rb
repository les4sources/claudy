module Reports
  # Ce que la cuisine a produit sur une plage de dates (epic #219, phase 5).
  #
  # La DATE DE RÉFÉRENCE d'une ligne est sa propre date quand elle en a une, et
  # à défaut l'arrivée du séjour : le funnel public accepte des repas sans date,
  # et une ligne sans date ne doit ni disparaître du reporting ni s'y ranger au
  # hasard. C'est un `COALESCE` en SQL pour que le filtrage et le regroupement
  # par mois se fassent en base, pas en Ruby sur toute la table.
  #
  # Seules les lignes `billable` comptent : une demande d'info n'engage rien, et
  # une ligne annulée ou refusée n'a rien produit.
  class KitchenRevenue
    REFERENCE_DATE = "COALESCE(meal_orders.date, stays.arrival_date)".freeze
    IN_RANGE = "#{REFERENCE_DATE} BETWEEN ? AND ?".freeze

    # Ce que la cuisine a FACTURÉ, rien de plus. Le coût ne se totalise plus ici
    # (epic #269) : les courses se font par lot, pour plusieurs services à la
    # fois, et une marge par ligne mentait. La dépense se lit en comptabilité,
    # sur les comptes de charge que désigne Paramètres > Cuisine.
    Totals = Struct.new(:price_cents, :people, :count, keyword_init: true)

    def initialize(from:, to:)
      @from = from
      @to   = to
    end

    # Lignes de la plage, décorées, dans l'ordre chronologique.
    def lines
      @lines ||= MealOrderDecorator.decorate_collection(scope.to_a)
    end

    def any? = lines.any?

    def totals = @totals ||= totals_for(lines)

    # Par famille, dans l'ordre du catalogue — on lit toujours les repas avant
    # les buffets, quelle que soit la plage.
    def by_family
      @by_family ||= MealOrder::FAMILIES.filter_map do |family|
        group = lines.select { |line| line.family == family }
        next if group.empty?

        [MealOrder::FAMILY_LABELS[family], totals_for(group)]
      end
    end

    def by_responsible
      @by_responsible ||= lines.group_by { |line| line.responsible_human&.name || "Personne" }
                               .sort_by { |name, _| name }
                               .map { |name, group| [name, totals_for(group)] }
    end

    # Chiffre d'affaires cuisine par mois, pour le reporting annuel.
    def self.revenue_by_month(year)
      MealOrder.billable
               .joins(:stay)
               .where(IN_RANGE, Date.new(year, 1, 1), Date.new(year, 12, 31))
               .group(Arel.sql("EXTRACT(MONTH FROM #{REFERENCE_DATE})::integer"))
               .sum(:price_cents)
    end

    private

    def scope
      MealOrder.billable
               .joins(:stay)
               .includes(:responsible_human, stay: :customer)
               .where(IN_RANGE, @from, @to)
               .order(Arel.sql("#{REFERENCE_DATE} ASC"), :id)
    end

    def totals_for(group)
      Totals.new(
        price_cents: group.sum { |line| line.price_cents.to_i },
        people:      group.sum { |line| line.people.to_i },
        count:       group.size
      )
    end
  end
end
