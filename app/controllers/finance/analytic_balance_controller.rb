module Finance
  # La balance analytique : ce que chaque pôle produit et ce qu'il coûte.
  #
  # La part NON AFFECTÉE est affichée comme telle et n'est jamais répartie
  # d'office. Un chiffre réparti au prorata a l'air complet et ne l'est pas ;
  # une ligne « non affecté » qui dérange est ce qui fait qu'on va l'affecter.
  class AnalyticBalanceController < Finance::AccountingBaseController
    breadcrumb "Balance analytique", :finance_analytic_balance_path, match: :exact

    def index
      @entities = LegalEntity.ordered
      @entity = LegalEntity.find_by(id: params[:legal_entity_id])
      @from = parsed_date(params[:from]) || Date.current.beginning_of_year
      @to = parsed_date(params[:to]) || Date.current.end_of_year

      scope = JournalLine.joins(:journal_entry, :general_account)
                         .where(journal_entries: { entry_date: @from..@to })
                         .where(general_accounts: { klass: [6, 7] })
      scope = scope.where(journal_entries: { legal_entity_id: @entity.id }) if @entity

      totals = scope.group(:team_id, "general_accounts.klass")
                    .pluck(Arel.sql("team_id, general_accounts.klass, SUM(debit_cents), SUM(credit_cents)"))

      teams = Team.where(id: totals.map(&:first).compact).index_by(&:id)
      @rows = totals.group_by(&:first).map do |team_id, lines|
        charges = lines.select { |l| l[1] == 6 }.sum { |l| l[2].to_i - l[3].to_i }
        produits = lines.select { |l| l[1] == 7 }.sum { |l| l[3].to_i - l[2].to_i }

        { team: teams[team_id], charges_cents: charges, revenue_cents: produits,
          net_cents: produits - charges }
      end.sort_by { |row| row[:team]&.name || "" }

      @unallocated = @rows.find { |row| row[:team].blank? }
      @rows = @rows.reject { |row| row[:team].blank? }
      @pending_entries = CashEntry.pending.count
    end

    private

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
