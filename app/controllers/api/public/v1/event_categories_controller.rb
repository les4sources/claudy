module Api
  module Public
    module V1
      class EventCategoriesController < BaseController
        # GET /api/public/v1/event_categories — toutes les catégories vivantes,
        # avec leur pôle de la charte (peut manquer tant que l'éditrice ne l'a
        # pas choisi) et leur couleur.
        def index
          @categories = EventCategory.order(:name, :id).to_a

          serve_cached(["event_categories", @categories.map(&:cache_key_with_version)])
        end
      end
    end
  end
end
