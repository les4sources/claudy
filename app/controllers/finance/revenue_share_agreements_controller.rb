module Finance
  # Comptabilité > Partages de revenus (issue #247).
  #
  # Un accord par hébergement partagé, et la liste de ses relevés. On ne
  # supprime pas un accord : on le désactive. Des relevés passés le portent, et
  # un trimestre reversé doit rester lisible trois ans plus tard.
  class RevenueShareAgreementsController < Finance::AccountingBaseController
    before_action :get_agreement, only: %i[show edit update deactivate reactivate]

    breadcrumb "Partages de revenus", :finance_revenue_share_agreements_path, match: :exact

    def index
      @agreements = RevenueShareAgreement.ordered
                                         .includes(:lodging, :revenue_share_statements)
    end

    def show
      @statements = @agreement.revenue_share_statements.recent_first
      @next_period = @agreement.next_period_to_report
      breadcrumb @agreement.lodging&.name.to_s, finance_revenue_share_agreement_path(@agreement)
    end

    def new
      @agreement = RevenueShareAgreement.new(share_percent: 50, period: "quarterly",
                                             starts_on: Date.current.beginning_of_year)
    end

    def create
      @agreement = RevenueShareAgreement.new(agreement_params)

      if @agreement.save
        redirect_to finance_revenue_share_agreement_path(@agreement),
                    notice: "Accord de partage créé pour #{@agreement.lodging&.name}."
      else
        flash.now[:alert] = @agreement.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @agreement.update(agreement_params)
        redirect_to finance_revenue_share_agreement_path(@agreement), notice: "Accord mis à jour."
      else
        flash.now[:alert] = @agreement.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def deactivate
      @agreement.update(active: false)
      redirect_to finance_revenue_share_agreements_path, notice: "Accord désactivé."
    end

    def reactivate
      @agreement.update(active: true)
      redirect_to finance_revenue_share_agreements_path, notice: "Accord réactivé."
    end

    private

    def get_agreement = @agreement = RevenueShareAgreement.find(params[:id])

    def agreement_params
      params.require(:revenue_share_agreement)
            .permit(:lodging_id, :beneficiary_name, :beneficiary_email, :beneficiary_iban,
                    :beneficiary_third_party_id, :share_percent, :period, :starts_on, :ends_on, :active)
    end

    def accounting_secondary = "revenue_shares"
  end
end
