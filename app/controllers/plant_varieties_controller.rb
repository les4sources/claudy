# Les variétés d'une espèce, depuis sa fiche (epic #348, phase 7) : ajout,
# renommage, suppression tant qu'aucune plante vivante ne la porte. Le nom des
# plantes n'est pas touché : c'est un texte libre (« Pommier Reinette cl »).
class PlantVarietiesController < BaseController
  before_action :get_species
  before_action :get_variety, only: %i[update destroy]

  def create
    variety = @species.varieties.new(name: variety_name)
    if variety.save
      redirect_to back_to_species, notice: "Variété « #{variety.name} » ajoutée."
    else
      redirect_to back_to_species, alert: error_for(variety)
    end
  end

  def update
    previous = @variety.name
    if @variety.update(name: variety_name)
      redirect_to back_to_species, notice: "« #{previous} » s'appelle désormais « #{@variety.name} »."
    else
      redirect_to back_to_species, alert: error_for(@variety)
    end
  end

  def destroy
    count = @variety.plants.alive.count
    if count.positive?
      redirect_to back_to_species,
                  alert: "« #{@variety.name} » est portée par #{count} plante#{'s' if count > 1} vivante#{'s' if count > 1} : " \
                         "changez-leur de variété d'abord."
    else
      @variety.soft_delete!(validate: false)
      redirect_to back_to_species, notice: "Variété « #{@variety.name} » supprimée."
    end
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def get_species
    @species = PlantSpecies.find(params[:map_espece_id])
  end

  def get_variety
    @variety = @species.varieties.find(params[:id])
  end

  def variety_name = params.dig(:plant_variety, :name).to_s

  def back_to_species = map_espece_path(@species, anchor: "varietes")

  def error_for(variety)
    name = variety.name.presence || "La variété"
    reasons = variety.errors[:name].presence || variety.errors.full_messages
    "#{variety.name.present? ? "« #{name} »" : name} : #{reasons.to_sentence}."
  end
end
