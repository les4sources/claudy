module Finance
  # L'échéancier comptable (Michael, 2026-09-28) — ce qui vivait dans la base
  # Notion « Échéancier comptable ».
  #
  # L'écran répond à une question : qu'est-ce qui tombe, et qu'est-ce qui est
  # déjà passé sans avoir été fait ? D'où l'ordre : le retard d'abord, puis les
  # trente prochains jours, puis le reste de l'horizon. Ce qui est fait descend
  # en bas, pour mémoire, et disparaît au bout de trois mois.
  class ComplianceDeadlinesController < AccountingBaseController
    SOON_DAYS = 30
    RECENT_DAYS = 90

    before_action :get_deadline, only: %i[show update start close reopen]

    breadcrumb "Échéancier", :finance_compliance_deadlines_path, match: :exact

    def index
      @today = Date.current
      @entities = LegalEntity.ordered
      @entity_id = params[:entity].presence&.to_i

      outstanding = scoped.outstanding.to_a
      @overdue = outstanding.select { |deadline| deadline.due_on < @today }
      @soon = outstanding.select { |deadline| deadline.due_on.between?(@today, @today + SOON_DAYS) }
      @later = outstanding.select { |deadline| deadline.due_on > @today + SOON_DAYS }

      recent = scoped.where(due_on: (@today - 1.year)..).to_a.select(&:closed?)
      @recent = recent.select { |deadline| (deadline.effective_done_on || deadline.due_on) >= @today - RECENT_DAYS }
                      .sort_by { |deadline| deadline.effective_done_on || deadline.due_on }
                      .reverse
    end

    def show
      breadcrumb @deadline.display_title, finance_compliance_deadline_path(@deadline), match: :exact
      @invoices = candidate_invoices
    end

    def update
      if @deadline.update(deadline_params)
        redirect_to finance_compliance_deadline_path(@deadline), notice: "L'échéance a été mise à jour."
      else
        redirect_to finance_compliance_deadline_path(@deadline), alert: @deadline.errors.full_messages.to_sentence
      end
    end

    def start
      @deadline.update!(status: "in_progress")
      redirect_back_or_to finance_compliance_deadline_path(@deadline), notice: "« #{@deadline.display_title} » est en cours."
    end

    # « Fait » ou « Sans objet ». Une échéance de paiement se clôt par sa
    # facture : la cocher à la main ferait mentir le rapprochement, d'où le refus
    # tant qu'une facture est liée.
    def close
      status = params[:status].presence_in(ComplianceDeadline::CLOSED_STATUSES) || "done"
      if @deadline.purchase_invoice.present?
        return redirect_back_or_to finance_compliance_deadline_path(@deadline),
                                   alert: "Cette échéance se solde par sa facture : elle sera faite quand la facture sera payée."
      end

      @deadline.close!(status: status, user: current_user)
      label = ComplianceDeadline::STATUS_LABELS.fetch(status).downcase
      redirect_back_or_to finance_compliance_deadlines_path, notice: "« #{@deadline.display_title} » : #{label}."
    end

    def reopen
      @deadline.reopen!
      redirect_back_or_to finance_compliance_deadline_path(@deadline), notice: "L'échéance est rouverte."
    end

    private

    def get_deadline
      @deadline = ComplianceDeadline.includes(compliance_obligation: :legal_entity).find(params[:id])
    end

    def scoped
      scope = ComplianceDeadline.includes(:purchase_invoice, compliance_obligation: :legal_entity).ordered
      @entity_id ? scope.for_entity(@entity_id) : scope
    end

    # Les factures qu'on peut lier : celles de la même entité, récentes, pas déjà
    # prises par une autre échéance. Payées comprises — un précompte réglé avant
    # d'avoir été rattaché doit pouvoir clore son échéance après coup.
    def candidate_invoices
      return PurchaseInvoice.none unless @deadline.payment?

      taken = ComplianceDeadline.where.not(id: @deadline.id).where.not(purchase_invoice_id: nil).select(:purchase_invoice_id)
      PurchaseInvoice.where(legal_entity_id: @deadline.legal_entity.id)
                     .where(issued_on: (@deadline.due_on - 1.year)..)
                     .where.not(id: taken)
                     .includes(:third_party)
                     .order(issued_on: :desc)
                     .limit(50)
    end

    def deadline_params
      params.require(:compliance_deadline).permit(:due_on, :note, :proof, :purchase_invoice_id)
    end

    def accounting_secondary = "deadlines"
  end
end
