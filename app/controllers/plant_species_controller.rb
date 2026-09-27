# L'autocomplétion de la fiche plante (epic #348, phase 7) : espèces, puis
# variétés d'une espèce, en JSON. Lecture seule — une espèce ou une variété
# nouvelle naît à l'enregistrement de la plante, par son nom
# (`PlantsController#assign_species`).
class PlantSpeciesController < BaseController
  LIMIT = 10

  # GET /map/species.json?q=pom
  def autocomplete
    species = PlantSpecies.search(params[:q]).ordered.limit(LIMIT)
    render json: species.map { |s| { id: s.id, name: s.name, latin_name: s.latin_name, label: s.full_name } }
  end

  # GET /map/species/:id/varieties.json?q=rei
  def varieties
    scope = PlantSpecies.find(params[:id]).varieties
    query = params[:q].to_s.squish
    scope = scope.where("plant_varieties.name ILIKE ?", "%#{PlantVariety.sanitize_sql_like(query)}%") if query.present?
    render json: scope.limit(LIMIT).map { |v| { id: v.id, name: v.name } }
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end
end
