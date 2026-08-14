module Finance
  # Le grand livre général : toutes les lignes d'un compte, dans l'ordre, avec le
  # solde qui court. C'est la lecture qui permet de répondre « d'où vient ce
  # chiffre » sans rouvrir un tableur.
  class LedgerController < Finance::BaseController
    breadcrumb "Comptabilité", :finance_accounting_path, match: :exact
    breadcrumb "Grand livre", :finance_ledger_path, match: :exact

    def index
      @accounts = GeneralAccount.ordered
      @entities = LegalEntity.ordered
      @account = GeneralAccount.find_by(id: params[:general_account_id])
      @entity = LegalEntity.find_by(id: params[:legal_entity_id])
      @from = parsed_date(params[:from]) || Date.current.beginning_of_year
      @to = parsed_date(params[:to]) || Date.current.end_of_year

      @lines = []
      return if @account.blank?

      scope = JournalLine.joins(:journal_entry)
                         .where(general_account_id: @account.id)
                         .where(journal_entries: { entry_date: @from..@to })
                         .includes(journal_entry: [:fiscal_year, :legal_entity])
                         .order("journal_entries.entry_date", "journal_entries.id")
      scope = scope.where(journal_entries: { legal_entity_id: @entity.id }) if @entity

      # Le solde d'ouverture est celui d'AVANT la période lue, sinon la première
      # ligne affichée semblerait sortir de nulle part.
      opening_scope = JournalLine.joins(:journal_entry)
                                 .where(general_account_id: @account.id)
                                 .where("journal_entries.entry_date < ?", @from)
      opening_scope = opening_scope.where(journal_entries: { legal_entity_id: @entity.id }) if @entity
      @opening_cents = opening_scope.sum(:debit_cents) - opening_scope.sum(:credit_cents)

      running = @opening_cents
      @lines = scope.map do |line|
        running += line.signed_cents
        [line, running]
      end
      @closing_cents = running
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
