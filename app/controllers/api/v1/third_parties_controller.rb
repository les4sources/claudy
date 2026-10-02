module Api
  module V1
    # Les tiers de la comptabilité, en LECTURE seule.
    #
    # Sert d'abord à résoudre un fournisseur par son nom avant de poser un palier
    # de prix (`third_party_id`) : un agent qui reprend une facture Interbio doit
    # retrouver le tiers qui existe déjà, pas en inventer un. La création reste
    # un geste humain dans Finances > Tiers. L'IBAN n'est jamais exposé.
    class ThirdPartiesController < BaseController
      def index
        scope = ThirdParty.ordered.search(params[:q])
        scope = scope.suppliers if params[:kind] == "supplier"
        scope = scope.customers if params[:kind] == "customer"
        scope = scope.actives if ActiveModel::Type::Boolean.new.cast(params[:active])

        @third_parties = paginate(scope)
      end
    end
  end
end
