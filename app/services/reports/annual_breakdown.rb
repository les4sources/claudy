module Reports
  # Les séries des deux graphes de `/reports` (issue #276).
  #
  # Le tableau mensuel de la page répond déjà à « combien », mois par mois. Il
  # ne répond pas à « quel gîte porte quel mois » ni à « ce que pèse chaque
  # activité dans l'année » : pour les lire, il faut additionner douze lignes de
  # tête. Ce service produit les deux séries qui manquent, sur EXACTEMENT les
  # mêmes sources que le tableau — c'est la condition pour que le graphe et le
  # tableau ne se contredisent jamais.
  #
  # Le bar et l'épicerie, eux, ne sont nulle part dans Claudy : ils se lisent en
  # comptabilité, sur les comptes de produit 701001 et 701002 (décision 4 de
  # l'issue). Les comptes sourciers ne portent que la consommation des
  # habitants, jamais celle des hôtes, et sous-estimeraient le bar sans qu'on
  # puisse dire de combien. Conséquence assumée : tant que l'année n'est pas
  # encodée, la part vaut zéro — et le service le DIT (`missing_accounting?`)
  # plutôt que de laisser croire à zéro euro de vente.
  class AnnualBreakdown
    BAR_ACCOUNT_CODE     = "701001".freeze
    GROCERY_ACCOUNT_CODE = "701002".freeze

    # Les couleurs des hébergements sont attachées à l'HÉBERGEMENT, pas à son
    # rang dans la liste : la Hulotte garde sa teinte d'une année à l'autre, et
    # la création d'un gîte ne repeint pas les autres. L'index se dérive donc de
    # l'id et de rien d'autre. Deux gîtes dont les ids diffèrent d'un multiple
    # de huit partageraient une teinte — la maison en compte six.
    LODGING_PALETTE = %w[#0d9488 #7c3aed #ea580c #0369a1 #be123c #4d7c0f #b45309 #db2777].freeze

    # Les réservations confirmées sans hébergement rattaché (chambres seules).
    # Elles ont une part à elles : sans elle, la somme des parts du graphe ne
    # vaudrait pas le total « Hébergements » du tableau, et le graphe mentirait.
    UNASSIGNED_COLOR = "#94a3b8".freeze
    UNASSIGNED_LABEL = "Chambres seules".freeze

    ACTIVITY_COLORS = {
      lodgings: "#0d9488",  # teal, comme la colonne Hébergements du tableau
      spaces: "#c026d3",    # fuchsia, comme la colonne Espaces
      coworking: "#f59e0b", # amber, comme les cartes Coworking
      kitchen: "#ea580c",   # orange, comme la colonne Cuisine
      bar: "#7c3aed",
      grocery: "#0891b2"
    }.freeze

    ACTIVITY_LABELS = {
      lodgings: "Hébergements",
      spaces: "Salles",
      coworking: "Coworking",
      kitchen: "Cuisine",
      bar: "Bar",
      grocery: "Épicerie"
    }.freeze

    # Une série du graphe en barres : douze valeurs, dans l'ordre des mois.
    Series = Struct.new(:key, :label, :color, :monthly_cents, :total_cents, keyword_init: true)

    # Une part de l'anneau. `state` distingue les trois situations que zéro euro
    # ne suffit pas à décrire : la vente réelle (`:present`), l'année pas encore
    # encodée (`:missing_accounting`) et le compte introuvable au plan comptable
    # (`:missing_account`).
    Slice = Struct.new(:key, :label, :color, :amount_cents, :state, keyword_init: true) do
      def missing_accounting? = state == :missing_accounting

      def missing_account? = state == :missing_account

      def unavailable? = missing_accounting? || missing_account?
    end

    def initialize(year:)
      @year = year.to_i
    end

    attr_reader :year

    # --- Graphe 1 : hébergements, mois par mois ------------------------------

    def lodging_series
      @lodging_series ||= begin
        cells = booking_cells
        keys_in_order(cells).map do |lodging_id|
          monthly = (1..12).map { |month| cells.fetch([lodging_id, month], 0).to_i }
          Series.new(
            key: lodging_id ? "lodging-#{lodging_id}" : "unassigned",
            label: lodging_id ? lodgings_by_id.fetch(lodging_id).name : UNASSIGNED_LABEL,
            color: lodging_id ? color_for(lodging_id) : UNASSIGNED_COLOR,
            monthly_cents: monthly,
            total_cents: monthly.sum
          )
        end
      end
    end

    def lodging_total_cents = lodging_series.sum(&:total_cents)

    # --- Graphe 2 : répartition annuelle du CA Accueil -----------------------

    def activity_slices
      @activity_slices ||= [
        slice(:lodgings, bookings_scope.sum(:price_cents).to_i),
        slice(:spaces, space_bookings_scope.sum(:price_cents).to_i),
        slice(:coworking, coworking_revenue_cents),
        slice(:kitchen, KitchenRevenue.revenue_by_month(year).values.sum.to_i),
        accounting_slice(:bar, BAR_ACCOUNT_CODE),
        accounting_slice(:grocery, GROCERY_ACCOUNT_CODE)
      ]
    end

    def activities_total_cents = activity_slices.sum { |slice| slice.amount_cents }

    private

    def year_range = Date.new(year, 1, 1)..Date.new(year, 12, 31)

    def bookings_scope
      Booking.where(status: "confirmed", from_date: year_range)
    end

    def space_bookings_scope
      SpaceBooking.where(status: "confirmed", from_date: year_range)
    end

    # Un seul regroupement SQL pour les 12 mois × n hébergements. `Lodging#revenues`
    # ferait une requête par case, soit 48 allers-retours pour dessiner un graphe.
    def booking_cells
      @booking_cells ||=
        bookings_scope.group(:lodging_id, Arel.sql("EXTRACT(MONTH FROM from_date)::integer"))
                      .sum(:price_cents)
    end

    # Les hébergements du reporting d'abord, dans l'ordre, puis ceux qui portent
    # des recettes sans y figurer — sinon leur montant disparaîtrait du graphe et
    # la somme des parts cesserait d'égaler le total du tableau. Les chambres
    # seules ferment la marche.
    def keys_in_order(cells)
      with_revenue = cells.keys.map(&:first).uniq
      ids = reported_lodging_ids + (with_revenue.compact - reported_lodging_ids).sort
      ids += [nil] if with_revenue.include?(nil)
      ids
    end

    def reported_lodging_ids
      @reported_lodging_ids ||= Lodging.where(show_on_reports: true).order(:id).pluck(:id)
    end

    def lodgings_by_id
      @lodgings_by_id ||= Lodging.where(id: keys_in_order(booking_cells).compact).index_by(&:id)
    end

    def color_for(lodging_id)
      LODGING_PALETTE[(lodging_id - 1) % LODGING_PALETTE.size]
    end

    def slice(key, amount_cents, state: :present)
      Slice.new(key: key, label: ACTIVITY_LABELS.fetch(key), color: ACTIVITY_COLORS.fetch(key),
                amount_cents: amount_cents, state: state)
    end

    # `paid?` et le prix d'un pack se calculent en Ruby : on reproduit ici le
    # calcul exact de la vue d'ensemble Coworking de la page, pour que la part
    # de l'anneau et la carte « CA coworking » disent le même chiffre.
    def coworking_revenue_cents
      CoworkingPack.where(purchased_at: year_range.first.beginning_of_day..year_range.last.end_of_day)
                   .select(&:paid?)
                   .sum(&:price_cents)
    end

    def accounting_slice(key, code)
      account = GeneralAccount.find_by(code: code)
      return slice(key, 0, state: :missing_account) if account.nil?

      lines = JournalLine.joins(:journal_entry)
                         .where(general_account_id: account.id)
                         .where(journal_entries: { entry_date: year_range })
      return slice(key, 0, state: :missing_accounting) if lines.count.zero?

      slice(key, lines.sum("credit_cents - debit_cents").to_i)
    end
  end
end
