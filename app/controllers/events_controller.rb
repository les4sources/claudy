class EventsController < BaseController
  before_action :get_event, only: [:show, :edit, :update, :destroy]

  breadcrumb "Événements", :events_path, match: :exact

  def index
    @events = EventDecorator
      .decorate_collection(Event.all.includes(:event_category).order(starts_at: :desc))
  end

  def show
    @event = EventDecorator.new(@event)
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
    @event.starts_at_date = @event.starts_at.to_date
    @event.ends_at_date = @event.ends_at.to_date
    @event.starts_at_time = @event.starts_at.to_time
    @event.ends_at_time = @event.ends_at.to_time
     # value: (f.object.starts_at.present? ? l(f.object.starts_at.to_time, format: :twenty_four_hour) : nil)

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
      render :edit, 
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def destroy
    if @event.soft_delete!(validate: false)
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
    @settings_view = true
  end
end
