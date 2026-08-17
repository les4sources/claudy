module Api
  module V1
    # Les axes analytiques (#196).
    #
    # Le plan comptable Winbooks porte le pôle DANS le numéro de compte. La
    # reprise en extrait un axe analytique par pôle, pour que l'écran Analytique
    # ait de quoi agréger sans avoir à relire des libellés.
    #
    # `team_id` reste vide quand aucune équipe de claudy ne correspond : Winbooks
    # connaît une quinzaine de pôles, claudy six. Inventer l'équipe manquante
    # produirait une hiérarchie que personne n'a décidée.
    class AnalyticAccountsController < BaseController
      before_action :get_account, only: [:show, :update]

      def index
        scope = AnalyticAccount.order(:code).includes(:team)
        scope = scope.where("analytic_accounts.code ILIKE :q OR analytic_accounts.name ILIKE :q",
                            q: "%#{params[:q]}%") if params[:q].present?
        scope = scope.where(team_id: params[:team_id]) if params[:team_id].present?

        @analytic_accounts = paginate(scope)
      end

      def show; end

      def create
        attributes = account_params
        @analytic_account = AnalyticAccount.find_or_initialize_by(code: attributes[:code])
        @created = @analytic_account.new_record?

        if @analytic_account.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@analytic_account)
        end
      end

      def update
        if @analytic_account.update(account_params)
          render :show
        else
          render_invalid(@analytic_account)
        end
      end

      private

      def get_account
        @analytic_account = AnalyticAccount.find(params[:id])
      end

      def account_params
        params.require(:analytic_account).permit(:code, :name, :team_id, :active)
      end
    end
  end
end
