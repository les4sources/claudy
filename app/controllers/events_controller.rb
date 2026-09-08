class EventsController < BaseController
  before_action :get_event, only: [:show, :edit, :update, :destroy, :duplicate, :publish, :unpublish]

  breadcrumb "Événements", :events_path, match: :exact

  STATES = %w[published draft].freeze

  def index
    scope = Event.all.includes(:event_category).order(starts_at: :desc)
    # Filtre par état de publication sur le site (`?state=published|draft`).
    @state = params[:state].presence_in(STATES)
    scope = scope.published if @state == "published"
    scope = scope.draft if @state == "draft"
    @events = EventDecorator.decorate_collection(scope)
    @counts = { all: Event.count, published: Event.published.count, draft: Event.draft.count }
  end

  def show
    @event = EventDecorator.new(@event)
  end

  def new
    @event = Event.new
  end

  # Formulaire de création prérempli depuis un événement existant — rien n'est
  # écrit en base tant que l'éditrice n'a pas choisi les nouvelles dates et
  # enregistré (voir `Events::DuplicateService`).
  def duplicate
    @duplicated_from = @event
    @event = Events::DuplicateService.new(event: @event).call
    render :new
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

  # Publication sur le site les4sources.be. Le slug (optionnel) n'est pris en
  # compte qu'à la première publication ; ensuite il est figé.
  def publish
    Events::PublishService.new(event: @event).publish!(slug: params[:slug])
    redirect_to event_path(@event),
                notice: "L'événement est publié sur le site : #{@event.public_path}"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to event_path(@event),
                alert: "Publication impossible : #{e.record.errors.full_messages.join(', ')}"
  end

  def unpublish
    Events::PublishService.new(event: @event).unpublish!
    redirect_to event_path(@event),
                notice: "L'événement n'est plus publié sur le site."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to event_path(@event),
                alert: "Dépublication impossible : #{e.record.errors.full_messages.join(', ')}"
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
