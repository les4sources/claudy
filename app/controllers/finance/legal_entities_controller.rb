module Finance
  # Les entités juridiques. La frontière entre elles n'est pas décorative : une
  # facture de travaux payée depuis le compte de la Fondation reste une charge de
  # la Société simple.
  class LegalEntitiesController < Finance::BaseController
    before_action :get_entity, only: [:edit, :update, :destroy]

    breadcrumb "Comptabilité", :finance_accounting_path, match: :exact
    breadcrumb "Entités", :finance_legal_entities_path, match: :exact

    def index
      @entities = LegalEntity.ordered.includes(:fiscal_years, :cash_accounts)
    end

    def new
      @entity = LegalEntity.new(form: "foundation", vat_regime: "exempt")
    end

    def create
      @entity = LegalEntity.new(entity_params)

      if @entity.save
        redirect_to finance_legal_entities_path, notice: "Entité « #{@entity.name} » créée."
      else
        flash.now[:alert] = @entity.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @entity.update(entity_params)
        redirect_to finance_legal_entities_path, notice: "Entité mise à jour."
      else
        flash.now[:alert] = @entity.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @entity.destroy
        redirect_to finance_legal_entities_path, notice: "Entité supprimée."
      else
        redirect_to finance_legal_entities_path,
                    alert: "Cette entité porte des exercices ou des écritures — désactive-la."
      end
    end

    private

    def get_entity = @entity = LegalEntity.find(params[:id])
    def finance_secondary = "accounting"

    def entity_params
      params.require(:legal_entity).permit(:name, :form, :vat_regime, :vat_number, :active)
    end
  end
end
