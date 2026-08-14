module Api
  module V1
    # Comptes courants internes (#155). LECTURE SEULE.
    #
    # Un compte s'ouvre et se ferme à la main, dans l'app : ce sont des personnes
    # et des ménages réels, pas des lignes qu'un agent doit pouvoir créer. Ce que
    # l'API sert ici, c'est la correspondance « nom de famille → compte », dont
    # un encodage de fiche papier a besoin avant d'écrire quoi que ce soit.
    #
    # Le solde n'est jamais stocké : il est recalculé pour toute la page en une
    # requête groupée (MemberAccounts::Summary), pas une par compte.
    class MemberAccountsController < BaseController
      def index
        scope = MemberAccount.ordered
        scope = scope.where("member_accounts.name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
        scope = scope.where(kind: params[:kind]) if params[:kind].present?

        active = ActiveModel::Type::Boolean.new.cast(params[:active])
        scope = active ? scope.actives : scope.inactives unless active.nil?

        @member_accounts = paginate(scope)
        MemberAccounts::Summary.new(@member_accounts).accounts
      end

      def show
        @member_account = MemberAccount.find(params[:id])
      end
    end
  end
end
