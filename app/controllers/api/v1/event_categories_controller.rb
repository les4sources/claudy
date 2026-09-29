module Api
  module V1
    # Les catégories d'événements. Leur `pole` donne la couleur et le
    # pictogramme des cartes sur le site : l'agent qui publie des événements
    # doit pouvoir le lire, et le poser quand l'équipe l'a choisi.
    class EventCategoriesController < BaseController
      def index
        @event_categories = EventCategory.order(:name)
      end

      def update
        @event_category = EventCategory.find(params[:id])
        if @event_category.update(event_category_params)
          render :show
        else
          render_invalid(@event_category)
        end
      end

      private

      # Le slug est la clé du site : il n'est pas modifiable ici.
      def event_category_params
        params.require(:event_category).permit(:name, :color, :pole)
      end
    end
  end
end
