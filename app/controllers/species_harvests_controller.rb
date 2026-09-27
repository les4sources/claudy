# Le calendrier de récolte PAR DÉFAUT d'une espèce (epic #348, phase 7), sur
# sa fiche : même éditeur que la fiche plante (`plants/_harvest_editor`). Les
# plantes sans calendrier propre le suivent. PATCH remplace toutes les
# fenêtres ; DELETE les efface. Réponse en Turbo Stream : seule la section
# « Récolte » de la fiche est remplacée.
class SpeciesHarvestsController < BaseController
  before_action :get_species

  def update
    parts = PlantHarvestWindow.parts_from_params(params.fetch(:harvest, {}).fetch(:parts, {}))
    draft, errors = PlantHarvestWindow.replace_for(@species, parts)
    @species.reload
    respond(draft: errors.any? ? draft : nil, errors: errors, saved: errors.empty?,
            status: errors.any? ? :unprocessable_content : :ok)
  end

  def destroy
    @species.harvest_windows.destroy_all
    @species.reload
    respond
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def get_species
    @species = PlantSpecies.includes(:harvest_windows).find(params[:map_espece_id])
  end

  def respond(draft: nil, errors: [], saved: false, status: :ok)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@species, :harvest),
                                                  partial: "plant_species/harvest",
                                                  locals: { species: @species, draft: draft, errors: errors, saved: saved }),
               status: status
      end
      format.html do
        redirect_to map_espece_path(@species), alert: errors.to_sentence.presence,
                                               notice: (saved ? "Calendrier de récolte enregistré." : nil)
      end
    end
  end
end
