class AgendaItemsController < BaseController
  layout :resolve_layout
  before_action :set_gathering, except: [:reorder_destroy]
  before_action :set_agenda_item, only: [:edit, :update, :destroy, :toggle_completed, :move]

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
    @old_list = @agenda_item.list
    service = AgendaItems::UpdateService.new(agenda_item: @agenda_item)
    if service.run(params)
      @agenda_item = AgendaItemDecorator.new(@agenda_item.reload)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to gathering_path(@gathering), notice: "Point mis à jour." }
      end
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

  def move
    target = Gathering.find(params[:target_gathering_id])
    if target.gathering_category_id != @gathering.gathering_category_id
      head :unprocessable_entity and return
    end
    if target.id == @gathering.id
      head :unprocessable_entity and return
    end
    next_position = (target.agenda_items.maximum(:position) || -1) + 1
    @agenda_item.update!(gathering_id: target.id, position: next_position)
    @target_gathering = target
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to gathering_path(@gathering), notice: "Point déplacé vers le prochain rassemblement." }
    end
  end

  def reorder
    list_key = params[:list].to_s
    list_value = AgendaItem.lists[list_key]
    ids = Array(params[:ids]).map(&:to_i)

    AgendaItem.transaction do
      ids.each_with_index do |id, index|
        attrs = { position: index }
        attrs[:list] = list_value if list_value
        @gathering.agenda_items.where(id: id).update_all(attrs)
      end
    end

    @list = list_key
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "agenda_items_counter_#{@gathering.id}_#{list_key}",
            partial: "agenda_items/counter",
            locals: { gathering: @gathering, list: list_key }
          ),
          turbo_stream.replace(
            "agenda_items_empty_#{@gathering.id}_#{list_key}",
            partial: "agenda_items/empty_state",
            locals: { gathering: @gathering, list: list_key }
          )
        ]
      end
      format.json { head :no_content }
    end
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

  def resolve_layout
    %w[edit update].include?(action_name) ? "modal" : "application"
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation"
    )
  end
end
