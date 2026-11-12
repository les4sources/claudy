module Finance
  # La porte d'entrée de la comptabilité (issue #177) : le référentiel d'un côté,
  # les deux lectures de l'autre. Un écran sans porte d'entrée n'est pas
  # vérifiable, et un référentiel qu'on ne trouve pas n'est jamais corrigé.
  class AccountingController < Finance::AccountingBaseController
    # La Comptabilité est aux Administratifs, la Situation financière aux
    # Sourciers (Michael, 2026-11-12). Un Sourcier qui ouvre l'ancienne porte
    # (favori, lien d'un mail) arrive sur la page qui lui est destinée, plutôt
    # que sur « Tu n'as pas accès ».
    prepend_before_action :redirect_to_situation, only: :index

    def index
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

    def redirect_to_situation
      return if current_user.nil? || current_user.can_read?(:accounting) || !current_user.can_read?(:situation)

      redirect_to finance_situation_path(params.permit(:entity).to_h)
    end

    # La nouvelle interface (Michael, 2026-11-12) : « À faire », la page des
    # comptables. La situation de chaque structure vit dans la Situation
    # financière (`Finance::SituationController`).
    def render_v2_index
      @page_guide_inline = true
      render "finance/accounting/v2/index"
    end
  end
end
