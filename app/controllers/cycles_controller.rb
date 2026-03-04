class CyclesController < BaseController
  before_action :get_cycle, only: [:edit, :update, :destroy]

  breadcrumb "Organisation", :organisation_path, match: :exact
  breadcrumb "Cycles", :cycles_path, match: :exact

  def index
    @cycles = Cycle.chronological
  end

  def new
    @cycle = Cycle.new
  end

  def create
    service = Cycles::CreateService.new
    if service.run(params)
      redirect_to cycles_path, notice: "Le cycle a été créé."
    else
      @cycle = service.cycle
      set_error_flash(service.cycle, service.error_message)
      render :new
    end
  end

  def edit
  end

  def update
    service = Cycles::UpdateService.new(cycle: @cycle)
    if service.run(params)
      redirect_to cycles_path, notice: "Le cycle a été mis à jour."
    else
      @cycle = service.cycle
      set_error_flash(service.cycle, service.error_message)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @cycle.soft_delete!(validate: false)
      redirect_to cycles_path, notice: "Le cycle '#{@cycle.name}' a été supprimé."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :edit
    end
  end

  private

  def get_cycle
    @cycle = Cycle.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation"
    )
    @organisation_view = true
  end
end
