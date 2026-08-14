module Api
  module V1
    # Catalogue du bar, du cellier et des repas (#157).
    #
    # C'est la première ressource de l'API à exposer la CRÉATION. La raison est
    # concrète : le catalogue du bar n'existe que sur une feuille A4, et le
    # remonter par un script versionné ferait entrer des données d'exploitation
    # dans un dépôt public. Elles passent donc par ici.
    #
    # POST est un UPSERT sur le couple (canal, nom) : reposter le même article
    # le met à jour au lieu d'en créer un second. Un agent qui rejoue son import
    # après une coupure ne doit pas se retrouver avec deux « Moinette » au bar.
    # La réponse dit lequel des deux s'est produit (`meta.created`).
    class CatalogItemsController < BaseController
      before_action :get_item, only: [:show, :update, :destroy]
      before_action :set_price_date

      def index
        scope = CatalogItem.ordered
                           .for_channel(params[:channel])
                           .matching(params[:q])
                           .includes(:catalog_prices)
        scope = scope.active if ActiveModel::Type::Boolean.new.cast(params[:active])

        @catalog_items = paginate(scope)
      end

      def show; end

      def create
        attributes = item_params
        @catalog_item = CatalogItem.find_or_initialize_by(
          channel: attributes[:channel], name: attributes[:name]
        )
        @created = @catalog_item.new_record?

        if @catalog_item.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@catalog_item)
        end
      end

      def update
        if @catalog_item.update(item_params)
          render :show
        else
          render_invalid(@catalog_item)
        end
      end

      def destroy
        @catalog_item.soft_delete!(validate: false)
        head :no_content
      end

      private

      def get_item
        @catalog_item = CatalogItem.includes(:catalog_prices).find(params[:id])
      end

      # `?on=2026-07-31` — le prix exposé est celui qui couvre CETTE date. Sans
      # ça, relire un mois clôturé afficherait les prix d'aujourd'hui.
      def set_price_date
        @on = (Date.parse(params[:on]) if params[:on].present?) || Date.current
      rescue Date::Error
        render json: { error: "unprocessable_entity", message: "Paramètre `on` invalide : attendu AAAA-MM-JJ." },
               status: :unprocessable_entity
      end

      def item_params
        params.require(:catalog_item).permit(:name, :channel, :category, :unit, :reference, :active)
      end
    end
  end
end
