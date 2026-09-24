# Notes de réunion d'un point de l'ODJ, dans une modale séparée du formulaire
# d'édition du point. Une note par (point, rassemblement) : on édite toujours
# celle du rassemblement courant, les précédentes restent en lecture seule.
class AgendaItemNotesController < BaseController
  layout "modal"
  before_action :set_gathering
  before_action :set_agenda_item
  before_action :set_note

  def edit
  end

  def update
    @note.body = params.dig(:agenda_item_note, :body)
    # Vider les notes supprime l'enregistrement : le point redevient « sans notes ».
    saved = @note.body.to_plain_text.blank? ? discard_note : @note.save
    if saved
      @agenda_item = AgendaItemDecorator.new(@agenda_item.reload)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to gathering_path(@gathering), notice: "Notes enregistrées." }
      end
    else
      set_error_flash(@note, "Les notes n'ont pas pu être enregistrées.")
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_gathering
    @gathering = Gathering.find(params[:gathering_id])
  end

  def set_agenda_item
    @agenda_item = @gathering.agenda_items.find(params[:agenda_item_id])
  end

  def set_note
    @note = @agenda_item.notes.find_or_initialize_by(gathering: @gathering)
  end

  def discard_note
    @note.persisted? ? @note.destroy.destroyed? : true
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation"
    )
  end
end
