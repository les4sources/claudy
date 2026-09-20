module Finance
  # Les entités juridiques. La frontière entre elles n'est pas décorative : une
  # facture de travaux payée depuis le compte de la Fondation reste une charge de
  # la Société simple.
  class LegalEntitiesController < Finance::AccountingBaseController
    before_action :get_entity, only: [:edit, :update, :destroy]
    breadcrumb "Entités", :finance_legal_entities_path, match: :exact

    def index
      @entities = LegalEntity.ordered.includes(:fiscal_years, :cash_accounts)
      # Les écritures se comptent en une requête groupée : les charger pour les
      # compter ferait remonter toute la comptabilité pour afficher un nombre.
      @entry_counts = JournalEntry.group(:legal_entity_id).count
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
        # Le motif est construit par le décorateur : il nomme ce qui bloque et,
        # quand seuls des exercices vides bloquent, mène au geste qui débloque.
        redirect_to finance_legal_entities_path, alert: @entity.decorate.deletion_refusal
      end
    end

    private

    def get_entity = @entity = LegalEntity.find(params[:id])

    def entity_params
      params.require(:legal_entity).permit(:name, :form, :vat_regime, :vat_number, :active)
    end
  end
end
