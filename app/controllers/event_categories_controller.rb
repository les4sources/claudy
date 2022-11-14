class EventCategoriesController < BaseController
  def index
    @event_categories = EventCategory.all.order(:name)
  end

  def show
    @event_category = EventCategory.find_by!(id: params[:id])
  end

  def new
    @event_category = EventCategory.new
  end

  def create
    service = EventCategories::CreateService.new
    if service.run(params)
      redirect_to service.event_category,
                  notice: "Merci, la catégorie d'événements a été créé."
    else
      @event_category = service.event_category
      set_error_flash(service.event_category, service.error_message)
      render :new
    end
  end

  def edit
    @event_category = EventCategory.find_by!(id: params[:id])
  end

  def update
    service = EventCategories::UpdateService.new(
      event_category: EventCategory.find(params[:id])
    )
    if service.run(params)
      redirect_to event_category_path(service.event_category),
                  notice: "La catégorie d'événements a été mise à jour."
    else
      @event_category = service.event_category
      set_error_flash(service.event_category, service.error_message)
      render :edit
    end
  end

  def destroy
    @event_category = EventCategory.find_by!(id: params[:id])
    @event_category.destroy
    redirect_to event_categories_url,
                status: :see_other,
                notice: "La catégorie d'événements a été supprimé."
  end

  private

  def event_category_params
    params
      .require(:event_category)
      .permit(
        :name,
        :color
      )
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "events",
      active_secondary: "event_categories"
    )
  end
end
