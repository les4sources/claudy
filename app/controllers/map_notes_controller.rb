# Les notes datées d'une plante, sur sa fiche (epic #348, phase 7) : « 12 mars
# — bourgeons gelés ». Ajout inline, suppression (soft-delete) ; chaque geste
# répond par un Turbo Stream qui remplace la seule section « Notes », sans
# toucher à la saisie en cours dans le dossier de la plante.
#
# Le porteur vient TOUJOURS de la route (`/map/plants/:plant_id/notes`) : le
# type polymorphe n'est jamais lu dans les paramètres.
class MapNotesController < BaseController
  access_section :map
  before_action :get_plant

  def create
    @note = @plant.map_notes.new(author: current_user)
    @note.assign_attributes(note_params)
    @note.noted_on ||= Date.current
    saved = @note.save
    respond(saved ? nil : @note, status: saved ? :ok : :unprocessable_content)
  end

  # La note d'une autre plante, ou déjà supprimée, n'existe pas ici : 404.
  def destroy
    @plant.map_notes.find(params[:id]).soft_delete!(validate: false)
    respond(nil)
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def get_plant
    @plant = Plant.find(params[:plant_id])
  end

  def note_params
    params.require(:map_note).permit(:body, :noted_on)
  end

  def respond(invalid_note, status: :ok)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@plant, :notes),
                                                  partial: "plants/notes",
                                                  locals: { plant: @plant.reload, invalid_note: invalid_note }),
               status: status
      end
      format.html do
        redirect_to map_path(feature: @plant.map_feature_id), alert: invalid_note&.errors&.full_messages&.to_sentence
      end
    end
  end
end
