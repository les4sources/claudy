class CyclesController < BaseController
  before_action :get_cycle, only: [:show, :edit, :update, :destroy, :closing, :close]

  breadcrumb "Organisation", :organisation_path, match: :exact
  breadcrumb "Cycles", :cycles_path, match: :exact

  def index
    @cycles = Cycle.chronological
  end

  # Bilan du cycle : ce que chaque membre a fait, reporté, abandonné.
  def show
    @reports = Cycles::MemberReport.for_cycle(@cycle)
    @next_cycle = @cycle.next_cycle
    @previous_cycle = @cycle.previous_cycle
    @totals = {
      planned: @reports.sum(&:planned_hours),
      done: @reports.sum(&:done_hours),
      deferred: @reports.sum(&:deferred_hours),
      dropped: @reports.sum(&:dropped_hours),
      pending: @reports.sum(&:pending_hours),
    }
  end

  # Rituel de clôture : triage de ce qui reste, puis verrouillage.
  def closing
    if @cycle.closed?
      redirect_to cycle_path(@cycle), notice: "Ce cycle est déjà clos."
      return
    end
    @reports = Cycles::MemberReport.for_cycle(@cycle).reject(&:empty?)
    @next_cycle = @cycle.next_cycle
    @pending_count = @reports.sum { |r| r.pending_actions.size }
    @rituelles_count = @cycle.cycle_actions.live.rituelle.count
    @reportees_count = @cycle.cycle_actions.live.reportee.where(completed: false).count
  end

  def close
    service = Cycles::CloseService.new(cycle: @cycle)
    if service.run
      s = service.summary
      redirect_to cycle_path(@cycle),
                  notice: "Cycle clos : #{s[:done]} faite#{'s' if s[:done] != 1}, #{s[:deferred]} passée#{'s' if s[:deferred] != 1} au suivant, #{s[:dropped]} abandonnée#{'s' if s[:dropped] != 1}."
    else
      redirect_to closing_cycle_path(@cycle), alert: service.error_message
    end
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
    if @cycle.cycle_actions.exists?
      redirect_to cycles_path, alert: "Ce cycle contient des actions : il ne peut pas être supprimé."
      return
    end
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
