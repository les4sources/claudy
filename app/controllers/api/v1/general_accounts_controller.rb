module Api
  module V1
    # Le plan comptable général (#196).
    #
    # Ouvert en écriture pour une raison précise : le vrai plan comptable des
    # 4 Sources n'existe que dans les bilans internes Winbooks, 146 comptes avec
    # l'analytique dans le numéro (`613313 Rémunérations Pôle Technique`). Le
    # dépôt étant public, il n'a pas sa place dans un seed versionné.
    #
    # POST est un UPSERT sur le CODE. Deux comptes `613313` rendraient toute
    # balance ininterprétable, et une reprise de 146 comptes se joue forcément
    # en plusieurs passes.
    class GeneralAccountsController < BaseController
      before_action :get_account, only: [:show, :update]

      def index
        scope = GeneralAccount.ordered
        scope = scope.where("general_accounts.code ILIKE :q OR general_accounts.name ILIKE :q",
                            q: "%#{params[:q]}%") if params[:q].present?
        scope = scope.in_class(params[:klass]) if params[:klass].present?
        scope = scope.where(nature: params[:nature]) if params[:nature].present?

        active = ActiveModel::Type::Boolean.new.cast(params[:active])
        scope = active ? scope.actives : scope.where(active: false) unless active.nil?

        @general_accounts = paginate(scope)
      end

      def show; end

      def create
        attributes = account_params
        @general_account = GeneralAccount.find_or_initialize_by(code: attributes[:code])
        @created = @general_account.new_record?

        if @general_account.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@general_account)
        end
      end

      def update
        if @general_account.update(account_params)
          render :show
        else
          render_invalid(@general_account)
        end
      end

      private

      # On adresse un compte par son CODE — c'est ce qu'un comptable connaît, et
      # c'est ce que porte le document repris. L'identifiant technique reste
      # accepté en second recours, pour les liens rendus par les autres vues.
      def get_account
        @general_account = GeneralAccount.find_by(code: params[:id]) || GeneralAccount.find(params[:id])
      end

      def account_params
        params.require(:general_account).permit(:code, :name, :klass, :nature, :reconcilable, :active)
      end
    end
  end
end
