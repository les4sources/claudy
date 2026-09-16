module Finance
  # Où va une catégorie de ventes Stripe (epic #250, phase 2).
  #
  # La correspondance se décidait jusqu'ici au rake, depuis le serveur. C'est une
  # décision de gestion — « le pain va en 700100, pôle Épicerie » — elle n'a rien
  # à faire derrière un accès SSH.
  #
  # Pas de `destroy` dur : une correspondance se retire en douceur (soft-delete),
  # parce que les lignes déjà affectées portent une COPIE de ses attributs et
  # doivent rester relisibles.
  class StripeCategoryMappingsController < AccountingBaseController
    breadcrumb "Stripe", :finance_stripe_path, match: :exact

    before_action :get_mapping, only: %i[edit update destroy]
    before_action :get_collections, only: %i[new create edit update]

    def new
      @mapping = StripeCategoryMapping.new(account_key: params[:account_key],
                                           category: params[:category].presence)
    end

    def create
      @mapping = StripeCategoryMapping.new(mapping_params)

      if @mapping.save
        redirect_to finance_stripe_path, notice: "Correspondance enregistrée."
      else
        flash.now[:alert] = @mapping.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @mapping.update(mapping_params)
        redirect_to finance_stripe_path, notice: "Correspondance mise à jour."
      else
        flash.now[:alert] = @mapping.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @mapping.soft_delete!
      redirect_to finance_stripe_path,
                  notice: "Correspondance retirée — les lignes déjà affectées gardent la leur."
    end

    private

    def get_mapping
      @mapping = StripeCategoryMapping.find(params[:id])
    end

    def get_collections
      @general_accounts = GeneralAccount.actives.ordered
      @teams = Team.ordered
      @entities = LegalEntity.actives.ordered
    end

    # `category` vide vaut « sans catégorie » — le modèle normalise en `nil`,
    # et c'est une valeur légitime, pas un champ oublié.
    def mapping_params
      params.require(:stripe_category_mapping)
            .permit(:account_key, :category, :general_account_id, :team_id, :legal_entity_id, :notes)
    end

    def accounting_secondary = "stripe"
  end
end
