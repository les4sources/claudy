module Api
  module V1
    # Les fiches des plantes bio-indicatrices (couche « Bio-indicatrices » de la
    # carte). L'analyse d'un relevé (par Claude) cherche ici la fiche de chaque
    # espèce vue, la crée à sa première rencontre, puis la cite dans l'analyse
    # écrite sur le relevé (`PATCH /api/v1/map_features/:id`).
    #
    # POST est un UPSERT sur le nom latin (casse ignorée) : une analyse rejouée
    # complète la fiche au lieu d'échouer. `meta.created` dit lequel des deux.
    class BioindicatorSpeciesController < BaseController
      include MapWriting

      def index
        scope = BioindicatorSpecies.ordered.search(params[:q])
        scope = scope.latin(params[:latin_name]) if params[:latin_name].present?
        @bioindicator_species_list = paginate(scope)
      end

      def show
        @bioindicator_species = BioindicatorSpecies.find(params[:id])
      end

      def create
        attributes = species_params
        return render_errors("latin_name est obligatoire") if attributes[:latin_name].blank?

        @bioindicator_species = BioindicatorSpecies.latin(attributes[:latin_name]).first || BioindicatorSpecies.new
        @created = @bioindicator_species.new_record?
        save_species(attributes, @created ? :created : :ok)
      end

      def update
        @bioindicator_species = BioindicatorSpecies.find(params[:id])
        save_species(species_params, :ok)
      end

      private

      def save_species(attributes, status)
        if @bioindicator_species.update(attributes)
          render :show, status: status
        else
          render_errors(@bioindicator_species.errors.full_messages)
        end
      end

      def species_params
        params.require(:bioindicator_species).permit(
          :name, :latin_name, :family, :common_names, :description, :biotope_primary, :biotope_secondary,
          :indicator_traits, :agronomy, :ecology, :notes, indicators: %i[key strength]
        )
      end
    end
  end
end
