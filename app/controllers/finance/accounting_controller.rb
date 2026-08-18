module Finance
  # La porte d'entrée de la comptabilité (issue #177) : le référentiel d'un côté,
  # les deux lectures de l'autre. Un écran sans porte d'entrée n'est pas
  # vérifiable, et un référentiel qu'on ne trouve pas n'est jamais corrigé.
  class AccountingController < Finance::AccountingBaseController

    def index
      @entities = LegalEntity.ordered.includes(:fiscal_years)
      @accounts_count = GeneralAccount.actives.count
      @entries_count = JournalEntry.count
      @open_years = FiscalYear.opened.includes(:legal_entity).ordered
    end
  end
end
