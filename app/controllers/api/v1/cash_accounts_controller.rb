module Api
  module V1
    # Les comptes de trésorerie (#198).
    #
    # Un import CODA refuse de créer le compte qu'il ne connaît pas — décider
    # qu'un compte bancaire existe, et avec quelle contrepartie générale, n'est
    # pas la responsabilité d'un import de fichier. Il faut donc pouvoir le créer
    # explicitement, en amont, et c'est ce que fait cet endpoint.
    #
    # Le compte général de contrepartie s'adresse par son CODE (`550000`) : c'est
    # ce que porte le plan comptable, et un identifiant technique ne survit pas à
    # une reprise de référentiel.
    class CashAccountsController < BaseController
      before_action :get_account, only: [:show, :update]

      def index
        scope = CashAccount.order(:name).includes(:general_account, :legal_entity)
        scope = scope.where(kind: params[:kind]) if params[:kind].present?
        scope = scope.actives if ActiveModel::Type::Boolean.new.cast(params[:active])

        @cash_accounts = paginate(scope)
      end

      def show; end

      def create
        attributes = account_params.merge(resolve_general_account)
        return if performed?

        @cash_account = CashAccount.find_or_initialize_by(name: attributes[:name])
        @created = @cash_account.new_record?

        if @cash_account.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@cash_account)
        end
      end

      def update
        attributes = account_params.merge(resolve_general_account)
        return if performed?

        if @cash_account.update(attributes)
          render :show
        else
          render_invalid(@cash_account)
        end
      end

      private

      def get_account
        @cash_account = CashAccount.find(params[:id])
      end

      def resolve_general_account
        code = params.require(:cash_account)[:general_account_code]
        return {} if code.blank?

        account = GeneralAccount.find_by(code: code)
        if account.nil?
          render json: { error: "unprocessable_entity",
                         message: "Compte général inconnu : #{code}." }, status: :unprocessable_entity
          return {}
        end

        { general_account_id: account.id }
      end

      def account_params
        params.require(:cash_account).permit(:name, :kind, :iban, :legal_entity_id,
                                             :general_account_id, :active, :stripe_account_key)
      end
    end
  end
end
