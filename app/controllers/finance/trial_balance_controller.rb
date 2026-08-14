module Finance
  # La balance : débit, crédit et solde par compte sur une période.
  #
  # Le total débit doit égaler le total crédit. Cette égalité affichée en gros
  # est tout l'intérêt de la partie double : c'est la comptabilité qui se
  # contredit toute seule quand quelque chose cloche, au lieu d'attendre qu'un
  # humain remarque l'écart six mois plus tard.
  class TrialBalanceController < Finance::BaseController
    breadcrumb "Comptabilité", :finance_accounting_path, match: :exact
    breadcrumb "Balance", :finance_trial_balance_path, match: :exact

    def index
      @entities = LegalEntity.ordered
      @entity = LegalEntity.find_by(id: params[:legal_entity_id])
      @from = parsed_date(params[:from]) || Date.current.beginning_of_year
      @to = parsed_date(params[:to]) || Date.current.end_of_year

      scope = JournalLine.joins(:journal_entry)
                         .where(journal_entries: { entry_date: @from..@to })
      scope = scope.where(journal_entries: { legal_entity_id: @entity.id }) if @entity

      totals = scope.group(:general_account_id)
                    .pluck(Arel.sql("general_account_id, SUM(debit_cents), SUM(credit_cents)"))

      accounts = GeneralAccount.where(id: totals.map(&:first)).index_by(&:id)
      @rows = totals.filter_map do |account_id, debit, credit|
        account = accounts[account_id]
        next if account.blank?

        { account: account, debit_cents: debit.to_i, credit_cents: credit.to_i,
          balance_cents: debit.to_i - credit.to_i }
      end.sort_by { |row| row[:account].code }

      @total_debit_cents = @rows.sum { |row| row[:debit_cents] }
      @total_credit_cents = @rows.sum { |row| row[:credit_cents] }
      @balanced = @total_debit_cents == @total_credit_cents
    end

    private

    def finance_secondary = "accounting"

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
