module Teams
  # Les comptes d'un pôle pour une année (Michael, 2026-10-18) : ce que les
  # membres du collectif viennent d'abord chercher sur la page du pôle.
  #
  #   * la SANTÉ : le résultat à date, ce qui va encore peser dessus (factures
  #     et notes de frais pas encore au grand livre) et un verdict ;
  #   * le BUDGET de l'année (`TeamBudget`) face au réel, au rythme de l'année ;
  #   * les DÉPENSES À VALIDER : les factures qui attendent le oui du pôle.
  #
  # Le réel se lit sur les écritures portant le `team_id` du pôle — jamais sur
  # une répartition au prorata : un chiffre réparti a l'air complet et ne l'est
  # pas. Un pôle qui en regroupe d'autres additionne les leurs (la hiérarchie
  # s'arrête à deux niveaux). Et tant que des lignes de trésorerie attendent
  # d'être affectées, le service le dit : elles ne sont dans aucun pôle.
  class Accounts
    # L'écart au budget toléré avant de passer « à surveiller » puis « hors
    # budget » : 10 % du plus gros des deux montants budgétés.
    TOLERANCE = 0.10
    RECENT_LIMIT = 15

    Totals = Struct.new(:revenue_cents, :expense_cents, keyword_init: true) do
      def net_cents = revenue_cents - expense_cents
      def any? = revenue_cents != 0 || expense_cents != 0
    end

    Budget = Struct.new(:revenue_cents, :expense_cents, :notes, :detailed, keyword_init: true) do
      def net_cents = revenue_cents - expense_cents
    end

    Month = Struct.new(:month, :revenue_cents, :expense_cents, keyword_init: true)

    SubTeam = Struct.new(:team, :totals, :budget_cents, keyword_init: true)

    Health = Struct.new(:level, :label, keyword_init: true)

    Snapshot = Struct.new(:revenue_cents, :expense_cents, :budget_expense_cents, :to_validate_count,
                          keyword_init: true) do
      def net_cents = revenue_cents - expense_cents
      def budget_percent = budget_expense_cents.to_i.positive? ? (expense_cents * 100.0 / budget_expense_cents).round : nil
    end

    # L'essentiel de chaque pôle pour l'annuaire, en trois requêtes quel que
    # soit le nombre de pôles. Un pôle qui en regroupe d'autres additionne les
    # leurs, comme sur sa page.
    def self.snapshots(teams, year:)
      period = Date.new(year, 1, 1)..Date.new(year, 12, 31)
      rows = JournalLine.joins(:journal_entry, :general_account)
                        .where(team_id: teams.map(&:id))
                        .where(journal_entries: { entry_date: period })
                        .where(general_accounts: { klass: [6, 7] })
                        .group(:team_id, "general_accounts.klass")
                        .pluck(Arel.sql("team_id, general_accounts.klass, SUM(debit_cents), SUM(credit_cents)"))
                        .group_by(&:first)
      budgets = budgets_by_team(teams.map(&:id), year)
      to_validate = PurchaseInvoice.where(status: "to_validate", validation_team_id: teams.map(&:id))
                                   .group(:validation_team_id).count

      teams.to_h do |team|
        ids = [team.id] + teams.select { |t| t.parent_id == team.id }.map(&:id)
        lines = ids.flat_map { |id| rows.fetch(id, []) }
        budget_cents = ids.filter_map { |id| budgets[id]&.expense_cents }
        [team.id, Snapshot.new(
          expense_cents: lines.select { |r| r[1] == 6 }.sum { |r| r[2].to_i - r[3].to_i },
          revenue_cents: lines.select { |r| r[1] == 7 }.sum { |r| r[3].to_i - r[2].to_i },
          budget_expense_cents: budget_cents.any? ? budget_cents.sum : nil,
          to_validate_count: ids.sum { |id| to_validate.fetch(id, 0) }
        )]
      end
    end

    def initialize(team:, year:, today: Date.current)
      @team = team
      @year = year.to_i
      @today = today
    end

    attr_reader :team, :year, :today

    def period = Date.new(year, 1, 1)..Date.new(year, 12, 31)

    # Le jour jusqu'auquel on compte : aujourd'hui pour l'année en cours, le
    # 31 décembre pour une année finie.
    def as_of = today.clamp(period.begin, period.end)

    def current_year? = period.cover?(today)

    def sub_teams = @sub_teams ||= team.children.ordered.to_a

    def team_ids = @team_ids ||= [team.id] + sub_teams.map(&:id)

    # La part de l'année écoulée : c'est elle qui dit si le pôle va trop vite.
    def elapsed_ratio
      return 0.0 if today < period.begin
      return 1.0 if today > period.end

      (as_of - period.begin + 1).to_f / (period.end - period.begin + 1)
    end

    # Toutes les écritures de l'année, y compris celles déjà datées plus tard
    # dans l'année (une charge fixe du mois, par exemple).
    def totals = @totals ||= totals_for(team_ids, period)

    # Même période l'an dernier, au jour près : comparer une année entière à
    # dix mois ferait toujours croire que le pôle se porte mieux qu'avant.
    # Le réel du pôle seul, sans ceux qu'il regroupe : c'est ce qui préremplit
    # son budget de l'année suivante.
    def own_totals = @own_totals ||= totals_for([team.id], period)

    def previous_totals
      @previous_totals ||= begin
        from = period.begin.prev_year
        totals_for(team_ids, from..(current_year? ? as_of.prev_year : period.end.prev_year))
      end
    end

    def net_cents = totals.net_cents

    # Ce qui va encore peser sur le résultat de l'année : les factures pas
    # encore validées (une facture n'entre au grand livre qu'au passage « À
    # payer ») et les notes de frais pas encore traitées, pour leur part
    # ventilée sur le pôle.
    def upcoming_invoices_cents
      @upcoming_invoices_cents ||=
        PurchaseInvoiceLine.joins(:purchase_invoice)
                           .where(team_id: team_ids)
                           .where(purchase_invoices: { status: %w[to_process to_validate],
                                                       issued_on: period, deleted_at: nil })
                           .sum(:amount_cents)
    end

    # La part de ces factures qui attend la validation d'un pôle : le reste est
    # encore en traitement à la comptabilité.
    def invoices_to_validate_lines_cents
      @invoices_to_validate_lines_cents ||=
        PurchaseInvoiceLine.joins(:purchase_invoice)
                           .where(team_id: team_ids)
                           .where(purchase_invoices: { status: "to_validate", issued_on: period, deleted_at: nil })
                           .sum(:amount_cents)
    end

    def upcoming_expense_reports_cents
      @upcoming_expense_reports_cents ||=
        ExpenseLine.joins(:expense_report)
                   .where(team_id: team_ids, spent_on: period)
                   .where(expense_reports: { status: "recorded", deleted_at: nil })
                   .sum(:amount_cents)
    end

    def upcoming_cents = upcoming_invoices_cents + upcoming_expense_reports_cents

    def projected_net_cents = net_cents - upcoming_cents

    # Les factures qui attendent le oui de ce pôle (ou d'un pôle qu'il
    # regroupe). Tant que personne n'a répondu, elles ne sont pas payables.
    def invoices_to_validate
      @invoices_to_validate ||=
        PurchaseInvoice.awaiting_validation_by(team_ids).ordered
                       .includes(:third_party, :validation_team).to_a
    end

    def invoices_to_validate_cents = invoices_to_validate.sum(&:total_cents)

    # Le budget de chaque pôle pour une année : ses lignes du budget détaillé
    # quand l'année en a (étape 4 du redressement), sinon ses deux montants
    # (`TeamBudget`). { team_id => Budget }, sans les pôles sans budget.
    def self.budgets_by_team(team_ids, year)
      simple = TeamBudget.where(team_id: team_ids, year: year).index_by(&:team_id)
      detailed = BudgetLine.team_totals(team_ids, year)
      team_ids.each_with_object({}) do |id, result|
        if detailed.key?(id)
          revenue, expense = detailed[id]
          result[id] = Budget.new(revenue_cents: revenue, expense_cents: expense, notes: simple[id]&.notes, detailed: true)
        elsif simple[id]
          result[id] = Budget.new(revenue_cents: simple[id].revenue_cents, expense_cents: simple[id].expense_cents,
                                  notes: simple[id].notes, detailed: false)
        end
      end
    end

    # Le budget de l'année, celui du pôle et de ceux qu'il regroupe. `nil`
    # quand personne n'en a fixé : on ne juge alors que le résultat.
    def budget
      return @budget if defined?(@budget)

      budgets = budgets_by_team.values
      @budget = if budgets.empty?
                  nil
                else
                  Budget.new(revenue_cents: budgets.sum(&:revenue_cents),
                             expense_cents: budgets.sum(&:expense_cents),
                             notes: budgets_by_team[team.id]&.notes,
                             detailed: budgets.any?(&:detailed))
                end
    end

    def budgets_by_team = @budgets_by_team ||= self.class.budgets_by_team(team_ids, year)

    def own_budget = TeamBudget.find_by(team_id: team.id, year: year)

    # Le résultat que le budget prévoit à ce stade de l'année, au prorata. Un
    # pôle saisonnier s'en écarte ; la page le dit.
    def expected_net_cents
      budget && (budget.net_cents * elapsed_ratio).round
    end

    def health
      @health ||=
        if budget.nil? && !totals.any? && upcoming_cents.zero?
          Health.new(level: :none, label: "Rien à juger")
        elsif budget
          gap = projected_net_cents - expected_net_cents
          threshold = TOLERANCE * [budget.revenue_cents, budget.expense_cents].max
          if gap >= 0
            Health.new(level: :good, label: "Dans le budget")
          elsif gap >= -threshold
            Health.new(level: :watch, label: "À surveiller")
          else
            Health.new(level: :alert, label: "Hors budget")
          end
        elsif projected_net_cents >= 0
          Health.new(level: :good, label: "À l'équilibre")
        else
          Health.new(level: :alert, label: "En déficit")
        end
    end

    # Les douze mois de l'année : ce que le pôle a produit et dépensé chaque mois.
    def months
      @months ||= begin
        rows = scope_for(team_ids, period)
               .group(Arel.sql("DATE_TRUNC('month', journal_entries.entry_date)"), "general_accounts.klass")
               .pluck(Arel.sql("DATE_TRUNC('month', journal_entries.entry_date), general_accounts.klass, " \
                               "SUM(debit_cents), SUM(credit_cents)"))
        by_month = rows.group_by { |row| row[0].to_date.month }

        (1..12).map do |month|
          lines = by_month.fetch(month, [])
          Month.new(month: Date.new(year, month, 1), **split(lines.map { |l| l[1..] }))
        end
      end
    end

    # Le détail par pôle regroupé, quand ce pôle en regroupe d'autres.
    def sub_team_rows
      return [] if sub_teams.empty?

      budgets = budgets_by_team
      ([team] + sub_teams).map do |t|
        SubTeam.new(team: t, totals: totals_for([t.id], period), budget_cents: budgets[t.id]&.expense_cents)
      end
    end

    # Ce que l'année a de produits et de charges rattachés à AUCUN pôle :
    # global, pas propre au pôle, mais c'est autant qui manque peut-être ici.
    def unassigned_totals = @unassigned_totals ||= totals_for([nil], period)

    def pending_entries_count = @pending_entries_count ||= CashEntry.pending.count

    def incomplete? = pending_entries_count.positive? || unassigned_totals.any?

    # Les dernières affectations de trésorerie du pôle, pour voir d'où viennent
    # les chiffres ; au-delà, on va au grand livre.
    def recent_allocations
      @recent_allocations ||=
        CashAllocation.joins(:cash_entry)
                      .includes(:general_account, :team, cash_entry: :cash_account)
                      .where(team_id: team_ids)
                      .where(cash_entries: { entry_date: period })
                      .order(Arel.sql("cash_entries.entry_date DESC, cash_allocations.id DESC"))
                      .limit(RECENT_LIMIT)
                      .to_a
    end

    private

    def scope_for(ids, dates)
      JournalLine.joins(:journal_entry, :general_account)
                 .where(team_id: ids)
                 .where(journal_entries: { entry_date: dates })
                 .where(general_accounts: { klass: [6, 7] })
    end

    def totals_for(ids, dates)
      rows = scope_for(ids, dates).group("general_accounts.klass")
                                  .pluck(Arel.sql("general_accounts.klass, SUM(debit_cents), SUM(credit_cents)"))
      Totals.new(**split(rows))
    end

    # Une charge se lit au débit, un produit au crédit.
    def split(rows)
      { expense_cents: rows.select { |r| r[0] == 6 }.sum { |r| r[1].to_i - r[2].to_i },
        revenue_cents: rows.select { |r| r[0] == 7 }.sum { |r| r[2].to_i - r[1].to_i } }
    end
  end
end
