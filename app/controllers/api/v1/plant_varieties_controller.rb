module Api
  module V1
    # Les variétés d'une espèce (epic #348, phase 8). POST est un UPSERT sur
    # (espèce, nom) : `meta.created` dit si la variété a été créée.
    class PlantVarietiesController < BaseController
      include MapWriting

      def index
        scope = PlantVariety.ordered.includes(:plant_species)
        scope = scope.where(plant_species_id: params[:plant_species_id]) if params[:plant_species_id].present?
        @plant_varieties = paginate(scope)
      end

      def show
        @plant_variety = PlantVariety.includes(:plant_species).find(params[:id])
      end

      def create
        attributes = params.require(:plant_variety).permit(:plant_species_id, :species_name, :name, :notes)
        species = resolve_species(attributes)
        return render_errors("plant_species_id ou species_name est obligatoire") unless species
        return render_errors("name est obligatoire") if attributes[:name].blank?

        @plant_variety = species.varieties.named(attributes[:name]).first
        @created = @plant_variety.nil?
        PlantVariety.transaction do
          @plant_variety ||= species.find_or_create_variety!(attributes[:name])
          @plant_variety.update!(notes: attributes[:notes]) if attributes.key?(:notes)
        end
        render :show, status: @created ? :created : :ok
      end

      private

      def resolve_species(attributes)
        if attributes[:plant_species_id].present?
          PlantSpecies.find(attributes[:plant_species_id])
        elsif attributes[:species_name].present?
          PlantSpecies.find_or_create_by_name!(attributes[:species_name])
        end
      end
    end
  end
end
