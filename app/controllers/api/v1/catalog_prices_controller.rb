module Api
  module V1
    # Paliers de prix datés d'un article (#157).
    #
    # La règle de non-chevauchement vit dans le modèle : poser un palier sur une
    # période déjà couverte répond 422 plutôt que d'écraser en silence. C'est
    # exactement le garde-fou qu'il faut à un agent qui rejoue un import — un
    # prix corrigé à la main ne doit pas être effacé par une reprise de feuille
    # papier. Pour changer un palier existant, il faut le viser explicitement
    # en PATCH.
    class CatalogPricesController < BaseController
      before_action :get_item
      before_action :get_price, only: [:update, :destroy]

      def index
        @catalog_prices = @catalog_item.catalog_prices.most_recent_first
      end

      def create
        @catalog_price = @catalog_item.catalog_prices.build(price_params)

        if @catalog_price.save
          render :show, status: :created
        else
          render_invalid(@catalog_price)
        end
      end

      def update
        if @catalog_price.update(price_params)
          render :show
        else
          render_invalid(@catalog_price)
        end
      end

      def destroy
        @catalog_price.destroy!
        head :no_content
      end

      private

      def get_item
        @catalog_item = CatalogItem.find(params[:catalog_item_id])
      end

      def get_price
        @catalog_price = @catalog_item.catalog_prices.find(params[:id])
      end

      def price_params
        params.require(:price).permit(:active_from, :active_until, :member_price_cents,
                                      :purchase_price_cents, :reference_price_cents,
                                      :public_price_cents, :note)
      end
    end
  end
end
