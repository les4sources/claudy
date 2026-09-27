# Le calendrier de récolte d'une plante, sur sa fiche (epic #348, phase 7).
#
# Tant que la plante n'a pas de fenêtre propre, elle HÉRITE de celles de son
# espèce (`Plant#harvest_windows_effective`). « Personnaliser » copie toutes les
# fenêtres de l'espèce sur la plante ; l'édition remplace ensuite l'ENSEMBLE de
# ses fenêtres d'un coup ; « Revenir au calendrier de l'espèce » les supprime.
#
# Chaque geste répond par un Turbo Stream qui remplace la seule section
# « Récolte » : la saisie en cours dans le dossier de la plante n'est pas perdue.
class PlantHarvestsController < BaseController
  before_action :get_plant

  # POST /map/plants/:plant_id/harvest/customize
  def customize
    if @plant.harvest_windows.empty? && @plant.plant_species
      PlantHarvestWindow.transaction do
        @plant.plant_species.harvest_windows.each do |window|
          @plant.harvest_windows.create!(part: window.part, months: window.months)
        end
      end
    end
    respond(editing: true)
  end

  # PATCH /map/plants/:plant_id/harvest — `harvest[parts][fruit][]=9`… Les
  # parties absentes des paramètres sont supprimées ; une partie présente sans
  # mois est refusée (422), pour ne pas effacer une récolte par mégarde.
  def update
    parts = PlantHarvestWindow.parts_from_params(params.fetch(:harvest, {}).fetch(:parts, {}))
    draft, errors = PlantHarvestWindow.replace_for(@plant, parts)
    @plant.reload
    return respond(editing: true, draft: draft, errors: errors, status: :unprocessable_content) if errors.any?

    respond
  end

  # DELETE /map/plants/:plant_id/harvest
  def destroy
    @plant.harvest_windows.destroy_all
    @plant.reload
    respond
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def get_plant
    @plant = Plant.includes(:harvest_windows, plant_species: :harvest_windows).find(params[:plant_id])
  end

  def respond(editing: false, draft: nil, errors: [], status: :ok)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@plant, :harvest),
                                                  partial: "plants/harvest",
                                                  locals: { plant: @plant, editing: editing, draft: draft, errors: errors }),
               status: status
      end
      format.html { redirect_to map_path(feature: @plant.map_feature_id), alert: errors.to_sentence.presence }
    end
  end
end
