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
    draft = submitted_parts.map { |part, months| PlantHarvestWindow.new(owner_type: "Plant", owner_id: @plant.id, part: part, months: months) }
    errors = draft.select { |window| Array(window.months).compact_blank.empty? }
                  .map { |window| "#{window.part_label} : cochez au moins un mois, ou retirez la partie." }

    if errors.empty?
      PlantHarvestWindow.transaction do
        @plant.harvest_windows.destroy_all
        invalid = draft.reject(&:save)
        errors = invalid.flat_map { |window| window.errors.map { |error| "#{window.part_label} : #{error.attribute == :months ? "les mois #{error.message}" : error.full_message}." } }
        raise ActiveRecord::Rollback if errors.any?
      end
    end

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

  # { "fruit" => ["", "9", "10"] } — seules les parties connues, dans l'ordre
  # de `PARTS`. Le type n'est jamais constantizé : c'est une simple clé.
  def submitted_parts
    raw = params.fetch(:harvest, {}).fetch(:parts, {})
    raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    PlantHarvestWindow::PARTS.keys.filter_map { |part| [part, Array(raw[part])] if raw.key?(part) }
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
