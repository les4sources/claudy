module Finance
  # Les relevés d'un accord de partage (issue #247).
  #
  # Deux gestes seulement, et l'ordre compte : générer produit un BROUILLON
  # qu'on relit, émettre en fait un document. Le second est irréversible — d'où
  # le premier.
  class RevenueShareStatementsController < Finance::AccountingBaseController
    before_action :get_statement, only: %i[show issue destroy mark_paid]

    breadcrumb "Partages de revenus", :finance_revenue_share_agreements_path, match: :exact

    def show
      @agreement = @statement.revenue_share_agreement
      @lines = @statement.revenue_share_statement_lines.chronological.includes(:booking)
      # Les écartées ne sont recalculées que sur un brouillon : sur un relevé
      # émis, elles n'auraient plus de sens — le document est figé, la période
      # a bougé depuis.
      @excluded = if @statement.draft?
                    RevenueShares::Selection.new(agreement: @agreement,
                                                 period_from: @statement.period_from,
                                                 period_to: @statement.period_to,
                                                 except_statement: @statement).excluded
                  else
                    []
                  end
    end

    def create
      agreement = RevenueShareAgreement.find(params[:revenue_share_agreement_id])
      from = params[:period_from].presence
      period = from ? Date.parse(from) : agreement.next_period_to_report&.first

      if period.blank?
        return redirect_to finance_revenue_share_agreement_path(agreement),
                           alert: "Aucune période close ne reste à relever."
      end

      statement = RevenueShares::Generate.new(agreement: agreement, period_from: period,
                                              whodunnit: current_user&.email).run!
      redirect_to finance_revenue_share_statement_path(statement),
                  notice: "Relevé #{statement.period_label} généré en brouillon."
    rescue RevenueShares::Generate::AlreadyReported, RevenueShares::Generate::NothingToReport => e
      redirect_to finance_revenue_share_agreement_path(agreement), alert: e.message
    end

    def issue
      RevenueShares::Issue.new(statement: @statement, whodunnit: current_user&.email).run!

      notice = if @statement.reload.sent_at.present?
                 "Relevé émis et envoyé à #{@statement.revenue_share_agreement.beneficiary_email}."
               else
                 "Relevé émis. Aucun email de bénéficiaire : partage le lien de la page à la main."
               end
      redirect_to finance_revenue_share_statement_path(@statement), notice: notice
    rescue RevenueShares::Issue::NoLines,
           Accounting::PostRevenueShareStatement::MissingAccount,
           Accounting::PostDocument::MissingFiscalYear => e
      redirect_to finance_revenue_share_statement_path(@statement), alert: e.message
    end

    # Le paiement se constate ici tant que la file « À payer » de l'epic #240
    # (phase 4) n'existe pas : le geste reste explicite et daté, et le jour où
    # le rapprochement bancaire posera le même statut, il n'y aura rien à
    # défaire.
    def mark_paid
      if @statement.issued?
        @statement.update(status: "paid", paid_on: params[:paid_on].presence || Date.current)
        redirect_to finance_revenue_share_statement_path(@statement), notice: "Relevé marqué payé."
      else
        redirect_to finance_revenue_share_statement_path(@statement),
                    alert: "Seul un relevé émis peut être marqué payé."
      end
    end

    def destroy
      agreement = @statement.revenue_share_agreement

      if @statement.draft?
        @statement.destroy
        redirect_to finance_revenue_share_agreement_path(agreement), notice: "Brouillon supprimé."
      else
        redirect_to finance_revenue_share_statement_path(@statement),
                    alert: "Un relevé émis ne se supprime pas — il se régularise au relevé suivant."
      end
    end

    private

    def get_statement = @statement = RevenueShareStatement.find(params[:id])

    def accounting_secondary = "revenue_shares"
  end
end
