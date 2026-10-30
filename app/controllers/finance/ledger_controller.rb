module Finance
  # Le grand livre général : toutes les lignes d'un compte, dans l'ordre, avec le
  # solde qui court. C'est la lecture qui permet de répondre « d'où vient ce
  # chiffre » sans rouvrir un tableur.
  class LedgerController < Finance::AccountingBaseController
    breadcrumb "Grand livre", :finance_ledger_path, match: :exact

    def index
      @accounts = GeneralAccount.ordered
      @entities = LegalEntity.ordered
      @account = GeneralAccount.find_by(id: params[:general_account_id])
      @entity = LegalEntity.find_by(id: params[:legal_entity_id])
      # Le filtre par tiers (2026-10-30), ouvert depuis la balance tiers.
      # « none » = les lignes posées sans tiers.
      @third_parties = ThirdParty.ordered
      @without_third_party = params[:third_party_id] == "none"
      @third_party = ThirdParty.find_by(id: params[:third_party_id]) unless @without_third_party
      @from = parsed_date(params[:from]) || Date.current.beginning_of_year
      @to = parsed_date(params[:to]) || Date.current.end_of_year

      @lines = []
      return if @account.blank?

      scope = JournalLine.joins(:journal_entry)
                         .where(general_account_id: @account.id)
                         .where(journal_entries: { entry_date: @from..@to })
                         .includes(:team, :third_party, journal_entry: [:fiscal_year, :legal_entity])
                         .order("journal_entries.entry_date", "journal_entries.id")
      scope = scope.where(journal_entries: { legal_entity_id: @entity.id }) if @entity
      scope = scope.where(third_party_id: third_party_filter) if third_party_filter?

      # Le solde d'ouverture est celui d'AVANT la période lue, sinon la première
      # ligne affichée semblerait sortir de nulle part. Il suit la convention
      # de `Accounting::Balances` : l'à-nouveau de l'exercice quand il existe,
      # et des charges et produits qui repartent de zéro chaque année.
      entities = @entity ? [@entity] : @entities.to_a
      @opening_cents = entities.sum { |entity| opening_cents(entity) }

      running = @opening_cents
      @lines = scope.map do |line|
        running += line.signed_cents
        [line, running]
      end
      @closing_cents = running
    end

    private

    def third_party_filter? = @without_third_party || @third_party.present?
    def third_party_filter = @third_party&.id

    def opening_cents(entity)
      balances = Accounting::Balances.new(entity)
      return balances.before(@from, only: [@account.id])[@account.id] unless third_party_filter?

      balances.before(@from, by_third_party: true, only: [@account.id])[[@account.id, third_party_filter]]
    end

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
