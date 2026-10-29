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
      # La trésorerie en résumé : le solde, ce qui rentre, ce qui sort, la
      # courbe. Le détail vit sur sa page.
      @treasury = Finance::Treasury.for_foundation
      # Les dettes et litiges sans facture, TOUTES entités : la trésorerie ne
      # lit que la Fondation, mais la SRL doit aussi voir ce qui pèse sur elle.
      @open_liabilities = Liability.open.includes(:legal_entity).to_a
      # Les prêts reçus, par prêteur (2026-10-13) : un prêt de trésorerie
      # gonfle la banque, il ne doit pas passer pour de la marge.
      @loans = Finance::Loans.new
      # « Peut-on dépenser ? », entité par entité (2026-10-13) : la réponse
      # franche, en tête de page.
      @verdicts = Finance::SpendingVerdict.for_all(loans: @loans)
      # « À faire » (2026-10-17) : les files dans l'ordre du travail, pour que
      # la personne qui démarre sache par où commencer.
      @todo = Finance::AccountingTodo.new
      render_v2_index if current_user&.new_interface?
    end

    # Le détail d'un montant de « Peut-on dépenser ? » (Michael, 2026-10-19) :
    # la liste qui fait la somme, lue dans le même verdict que l'encart. Le
    # layout `modal`, comme le poste d'un compte : celui de l'application porte
    # déjà un cadre « modal » vide, que Turbo prendrait à la place du nôtre.
    def verdict_detail
      @part = params[:part]
      @verdict = Finance::SpendingVerdict.new(legal_entity: LegalEntity.actives.find(params[:legal_entity_id]))
      render layout: "modal"
    end

    private

    # La nouvelle interface (redesign, Michael 2026-10-29) : la même page, lue
    # pour UNE entité à la fois (`?entity=`, la Fondation d'abord). Le verdict,
    # les chiffres, la courbe, les échéances, les dettes et les prêts sont ceux
    # de l'entité choisie ; « À faire » reste commun, les files n'ont pas
    # d'entité. L'aide de l'écran se pose sous l'en-tête, pas au-dessus.
    def render_v2_index
      @verdict = @verdicts.find { |verdict| verdict.entity.id.to_s == params[:entity].to_s } || @verdicts.first
      entity = @verdict&.entity
      deadlines = @deadlines_overdue + @deadlines_soon
      @entity_deadlines = entity ? deadlines.select { |deadline| deadline.legal_entity == entity } : deadlines
      @entity_liabilities = entity ? @open_liabilities.select { |liability| liability.legal_entity == entity } : @open_liabilities
      @entity_loans = entity && @loans.groups.find { |group| group.entity == entity }
      @page_guide_inline = true
      render "finance/accounting/v2/index"
    end
  end
end
