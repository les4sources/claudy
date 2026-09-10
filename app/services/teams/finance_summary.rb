module Teams
  # Ce que le pôle produit, ce qu'il coûte, et d'où ça vient (epic #239, phase 3).
  #
  # Les chiffres se lisent sur les écritures — `JournalLine` portant le `team_id`
  # du pôle — et jamais sur une répartition au prorata : un chiffre réparti a
  # l'air complet et ne l'est pas. C'est aussi pourquoi le service expose le
  # nombre de lignes de trésorerie encore NON AFFECTÉES : sans ce rappel, la
  # page laisse croire que le pôle est entièrement mesuré alors qu'une part de
  # l'argent n'a pas encore été rattachée.
  class FinanceSummary
    # Les vingt dernières affectations suffisent à comprendre d'où viennent les
    # chiffres ; au-delà, on va au grand livre.
    ALLOCATIONS_LIMIT = 20

    def initialize(team:, from:, to:, legal_entity: nil)
      @team = team
      @from = from
      @to = to
      @legal_entity = legal_entity
    end

    attr_reader :team, :from, :to, :legal_entity

    def revenue_cents = totals[:revenue]

    def expense_cents = totals[:expense]

    def net_cents = revenue_cents - expense_cents

    def any_movement? = revenue_cents != 0 || expense_cents != 0 || recent_allocations.any?

    # Les affectations de trésorerie du pôle, la plus récente d'abord.
    def recent_allocations
      @recent_allocations ||=
        CashAllocation.joins(:cash_entry)
                      .includes(:general_account, :legal_entity, cash_entry: :cash_account)
                      .where(team_id: team.id)
                      .where(cash_entries: { entry_date: from..to })
                      .order(Arel.sql("cash_entries.entry_date DESC, cash_allocations.id DESC"))
                      .limit(ALLOCATIONS_LIMIT)
                      .to_a
    end

    # Global, pas propre au pôle : ce sont les lignes qui n'ont encore été
    # rattachées à RIEN, donc celles qui manquent à tous les pôles à la fois.
    def unallocated_entries_count
      @unallocated_entries_count ||= CashEntry.pending.count
    end

    private

    def totals
      @totals ||= begin
        scope = JournalLine.joins(:journal_entry, :general_account)
                           .where(team_id: team.id)
                           .where(journal_entries: { entry_date: from..to })
                           .where(general_accounts: { klass: [6, 7] })
        scope = scope.where(journal_entries: { legal_entity_id: legal_entity.id }) if legal_entity

        rows = scope.group("general_accounts.klass")
                    .pluck(Arel.sql("general_accounts.klass, SUM(debit_cents), SUM(credit_cents)"))

        expense = rows.select { |row| row[0] == 6 }.sum { |row| row[1].to_i - row[2].to_i }
        revenue = rows.select { |row| row[0] == 7 }.sum { |row| row[2].to_i - row[1].to_i }
        { expense: expense, revenue: revenue }
      end
    end
  end
end
