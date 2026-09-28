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
      # Le rappel de comptage (epic #243, phase 3, décision 5) : pas de
      # scheduler, pas d'email — un encart sur la page qu'on ouvre de toute
      # façon. Seul un comptage VALIDÉ compte : un brouillon est un comptage
      # qu'on n'a pas fini.
      @last_cash_count = CashCount.validated.ordered.first
      @days_since_cash_count = @last_cash_count && (Date.current - @last_cash_count.counted_on).to_i
      # L'échéancier comptable, en un encart : ce qui est dépassé, ce qui tombe
      # dans le mois. Le détail vit sur sa page.
      outstanding = ComplianceDeadline.outstanding.where(due_on: ..(Date.current + 30)).ordered.includes(:compliance_obligation).to_a
      @deadlines_overdue = outstanding.select(&:overdue?)
      @deadlines_soon = outstanding.reject(&:overdue?)
    end
  end
end
