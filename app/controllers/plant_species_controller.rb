# Le catalogue des espèces nourricières (epic #348, phase 7).
#
# `/map/especes` : la liste des espèces (plantes vivantes, calendrier de
# récolte par défaut en miniature), et la fiche d'une espèce — botanique,
# fenêtres de récolte par défaut (`SpeciesHarvestsController`), variétés
# (`PlantVarietiesController`), plantes. Une espèce ne se supprime pas tant que
# des plantes vivantes en dépendent.
#
# `/map/species.json` reste l'autocomplétion de la fiche plante : lecture
# seule — une espèce ou une variété nouvelle y naît à l'enregistrement de la
# plante, par son nom (`PlantsController#assign_species`).
class PlantSpeciesController < BaseController
  LIMIT = 10
  # Les expositions proposées d'office ; une valeur importée hors liste reste
  # affichée et cochée.
  EXPOSURES = %w[Soleil Mi-ombre Ombre].freeze

  before_action :get_species, only: %i[show update destroy]

  # GET /map/especes?q=pom
  def index
    @query = params[:q].to_s.squish.presence
    @species = PlantSpecies.search(@query).ordered.includes(:harvest_windows).to_a
    alive = Plant.alive.where(plant_species_id: @species.map(&:id))
    @plant_counts = alive.group(:plant_species_id).count
    @unplaced_counts = alive.to_place.group(:plant_species_id).count
  end

  def show
    load_show
  end

  def update
    if @species.update(species_params)
      redirect_to map_espece_path(@species), notice: "« #{@species.name} » enregistrée."
    else
      load_show
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    alive = @species.plants.alive.count
    if alive.positive?
      redirect_to map_espece_path(@species),
                  alert: "Impossible de supprimer « #{@species.name} » : " \
                         "#{alive} plante#{'s' if alive > 1} vivante#{'s' if alive > 1} " \
                         "en dépend#{'ent' if alive > 1}. Rattachez-les d'abord à une autre espèce."
    else
      @species.soft_delete!(validate: false)
      redirect_to map_especes_path, notice: "« #{@species.name} » a été retirée du catalogue."
    end
  end

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

  def get_species
    @species = PlantSpecies.includes(:harvest_windows).find(params[:id])
  end

  def load_show
    @plants = @species.plants.includes(:plant_variety).with_attached_photos.ordered.to_a
    @varieties = @species.varieties.to_a
    @variety_counts = @species.plants.alive.group(:plant_variety_id).count
  end

  def species_params
    params.require(:plant_species).permit(:name, :latin_name, :family, :common_names, :hardiness, :height, :spread,
                                          :wikipedia_url, :notes, exposure: [], edible_parts: [])
  end
end
