class GatheringActionsController < BaseController
  before_action :set_gathering
  before_action :set_gathering_action, only: [:show, :edit, :update, :destroy, :toggle_completed]

  def create
    service = GatheringActions::CreateService.new(gathering: @gathering)
    if service.run(params)
      @gathering_action = service.gathering_action
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to gathering_path(@gathering), notice: "Action ajoutée." }
      end
    else
      set_error_flash(service.gathering_action, service.error_message)
      redirect_to gathering_path(@gathering), alert: service.error_message
    end
  end

  def show
  end

  def edit
  end

  def update
    service = GatheringActions::UpdateService.new(gathering_action: @gathering_action)
    if service.run(params)
      respond_to do |format|
        # Replaces the row (gathering page) and the member-dashboard row, swapping
        # the inline edit form back to the updated display.
        format.turbo_stream { render :toggle_completed }
        format.html { redirect_to gathering_path(@gathering), notice: "Action mise à jour." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @gathering_action.soft_delete!(validate: false)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to gathering_path(@gathering), notice: "Action supprimée." }
    end
  end

  def toggle_completed
    @gathering_action.toggle_completed!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: gathering_path(@gathering) }
    end
  end

  private

  def set_gathering
    @gathering = Gathering.find(params[:gathering_id])
  end

  def set_gathering_action
    @gathering_action = @gathering.gathering_actions.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "organisation")
  end
end
