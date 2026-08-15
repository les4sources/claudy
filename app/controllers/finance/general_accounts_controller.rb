module Finance
  # Le plan comptable, éditable. C'est un référentiel de DÉPART : le plan réel de
  # la Fondation appartient au comptable, et cet écran existe pour qu'il le
  # corrige sans qu'on ait à écrire une migration.
  class GeneralAccountsController < Finance::BaseController
    before_action :get_account, only: [:edit, :update, :destroy]

    breadcrumb "Comptabilité", :finance_accounting_path, match: :exact
    breadcrumb "Plan comptable", :finance_general_accounts_path, match: :exact

    def index
      @klass = params[:klass].presence
      @accounts = GeneralAccount.ordered
      @accounts = @accounts.in_class(@klass) if @klass
    end

    def new
      @account = GeneralAccount.new(klass: params[:klass].presence || 6, nature: "expense")
    end

    def create
      @account = GeneralAccount.new(account_params)

      if @account.save
        redirect_to finance_general_accounts_path, notice: "Compte #{@account.code} créé."
      else
        flash.now[:alert] = @account.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @account.update(account_params)
        redirect_to finance_general_accounts_path, notice: "Compte #{@account.code} mis à jour."
      else
        flash.now[:alert] = @account.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # Un compte déjà mouvementé ne se supprime pas — `restrict_with_error` le
    # refuse, et c'est voulu : il se désactive.
    def destroy
      if @account.destroy
        redirect_to finance_general_accounts_path, notice: "Compte supprimé."
      else
        redirect_to finance_general_accounts_path,
                    alert: "Ce compte porte des écritures — désactive-le plutôt que de le supprimer."
      end
    end

    private

    def get_account = @account = GeneralAccount.find(params[:id])
    def finance_secondary = "accounting"

    def account_params
      params.require(:general_account).permit(:code, :name, :klass, :nature, :reconcilable, :active)
    end
  end
end
