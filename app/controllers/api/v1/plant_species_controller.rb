module Api
  module V1
    # Le catalogue local des espèces nourricières (epic #348, phase 8).
    #
    # POST est un UPSERT sur le nom (casse ignorée), comme le catalogue du bar :
    # un import Notion rejoué complète la fiche au lieu d'échouer sur « existe
    # déjà ». `meta.created` dit lequel des deux s'est produit.
    class PlantSpeciesController < BaseController
      include MapWriting

      def index
        scope = PlantSpecies.ordered.search(params[:q]).includes(:harvest_windows, :varieties)
        @plant_species_list = paginate(scope)
      end

      def show
        @plant_species = PlantSpecies.includes(:harvest_windows, :varieties).find(params[:id])
      end

      def create
        attributes = species_params
        return render_errors("name est obligatoire") if attributes[:name].blank?

        @plant_species = PlantSpecies.named(attributes[:name]).first || PlantSpecies.new
        @created = @plant_species.new_record?
        save_species(attributes, @created ? :created : :ok)
      end

      def update
        @plant_species = PlantSpecies.find(params[:id])
        save_species(species_params, :ok)
      end

      private

      def save_species(attributes, status)
        errors = []
        windows = harvest_windows_param(:plant_species, errors)
        return render_errors(errors) if errors.any?

        PlantSpecies.transaction do
          @plant_species.update!(attributes)
          replace_harvest_windows!(@plant_species, windows)
        end
        render :show, status: status
      end

      def species_params
        params.require(:plant_species).permit(:name, :latin_name, :family, :common_names, :hardiness, :height,
                                              :spread, :wikipedia_url, :notes, exposure: [], edible_parts: [])
      end
    end
  end
end
