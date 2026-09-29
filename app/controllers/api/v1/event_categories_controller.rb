module Api
  module V1
    # Les catégories d'événements. Leur `pole` donne la couleur et le
    # pictogramme des cartes sur le site : l'agent qui publie des événements
    # doit pouvoir le lire, et le poser quand l'équipe l'a choisi.
    #
    # POST crée une catégorie, ou met à jour celle dont le slug (dérivé du nom
    # quand il n'est pas fourni) existe déjà : rejouer l'appel ne la double
    # pas, et `meta.created` dit lequel des deux s'est produit.
    class EventCategoriesController < BaseController
      def index
        @event_categories = EventCategory.order(:name)
      end

      def create
        attributes = event_category_params
        slug = (attributes[:slug].presence || attributes[:name]).to_s.parameterize.presence
        @event_category = (EventCategory.find_by(slug: slug) if slug) || EventCategory.new(slug: slug)
        @created = @event_category.new_record?

        if @event_category.update(attributes.except(:slug))
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@event_category)
        end
      end

      def update
        @event_category = EventCategory.find(params[:id])
        if @event_category.update(event_category_params.except(:slug))
          render :show
        else
          render_invalid(@event_category)
        end
      end

      private

      # Le slug est la clé du site : posé à la création, jamais modifié ensuite.
      def event_category_params
        params.require(:event_category).permit(:name, :color, :pole, :slug)
      end
    end
  end
end
