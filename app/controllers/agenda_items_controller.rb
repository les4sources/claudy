class AgendaItemsController < BaseController
  before_action :set_gathering, except: [:reorder_destroy]
  before_action :set_agenda_item, only: [:edit, :update, :destroy, :toggle_completed]

  def new
    @agenda_item = @gathering.agenda_items.build
  end

  def create
    service = AgendaItems::CreateService.new(gathering: @gathering, author: current_human)
    if service.run(params)
      @agenda_item = AgendaItemDecorator.new(service.agenda_item)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to gathering_path(@gathering), notice: "Point ajouté à l'ODJ." }
      end
    else
      @agenda_item = service.agenda_item
      set_error_flash(service.agenda_item, service.error_message)
      respond_to do |format|
        format.html { redirect_to gathering_path(@gathering), alert: service.error_message }
      end
    end
  end

  def edit
  end

  def update
    service = AgendaItems::UpdateService.new(agenda_item: @agenda_item)
    if service.run(params)
      redirect_to gathering_path(@gathering), notice: "Point mis à jour."
    else
      set_error_flash(@agenda_item, service.error_message)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @agenda_item.soft_delete!(validate: false)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to gathering_path(@gathering), notice: "Point supprimé." }
    end
  end

  def toggle_completed
    @agenda_item.update!(completed: !@agenda_item.completed)
    @agenda_item = AgendaItemDecorator.new(@agenda_item)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to gathering_path(@gathering) }
    end
  end

  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    AgendaItem.transaction do
      ids.each_with_index do |id, index|
        @gathering.agenda_items.where(id: id).update_all(position: index)
      end
    end
    head :no_content
  end

  private

  def set_gathering
    @gathering = Gathering.find(params[:gathering_id])
  end

  def set_agenda_item
    @agenda_item = @gathering.agenda_items.find(params[:id])
  end

  def current_human
    current_user&.human || Human.where(status: "active").first
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation"
    )
  end
end
