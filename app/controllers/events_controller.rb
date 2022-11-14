class EventsController < BaseController
  before_action :get_event, only: [:show, :edit, :update, :destroy]

  def index
    @events = Event.all.order(starts_at: :desc)
  end

  def show
  end

  def new
    @event = Event.new
  end

  def create
    service = Events::CreateService.new
    if service.run(params)
      redirect_to event_path(service.event),
                  notice: "Super! L'événement a été ajouté."
    else
      @event = service.event
      set_error_flash(service.event, service.error_message)
      render :new
    end
  end

  def edit
  end

  def update
    service = Events::UpdateService.new(
      event: Event.find(params[:id])
    )
    if service.run(params)
      redirect_to event_path(service.event),
                  notice: "L'événement a été mis à jour."
    else
      @event = service.event
      set_error_flash(service.event, service.error_message)
      render :edit
    end
  end

  def destroy
    if @event.destroy
      redirect_to events_path,
                  notice: "L'événement a été supprimé."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :show
    end
  end

  private

  def get_event
    @event = Event.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "events",
      active_secondary: "events"
    )
  end
end
