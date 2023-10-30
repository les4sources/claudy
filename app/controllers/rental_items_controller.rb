class RentalItemsController < BaseController
  before_action :get_rental_item, only: [:show, :edit, :update, :destroy]

  breadcrumb "Objets à louer", :rental_items_path, match: :exact

  def index
    @rental_items = RentalItemDecorator
      .decorate_collection(RentalItem.all.order(name: :asc))
  end

  def show
    @rental_item = RentalItemDecorator.new(@rental_item)
  end

  def new
    @rental_item = RentalItem.new
  end

  def create
    service = RentalItems::CreateService.new
    if service.run(params)
      redirect_to rental_item_path(service.rental_item),
                  notice: "Super! L'objet '#{service.rental_item.name}' a été ajouté."
    else
      @rental_item = service.rental_item
      set_error_flash(service.rental_item, service.error_message)
      render :new,
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def edit
  end

  def update
    service = RentalItems::UpdateService.new(
      rental_item: RentalItem.find(params[:id])
    )
    if service.run(params)
      redirect_to rental_item_path(service.rental_item),
                  notice: "L'objet a été mis à jour."
    else
      @rental_item = service.rental_item
      set_error_flash(service.rental_item, service.error_message)
      render :edit, 
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def destroy
    if @rental_item.soft_delete!(validate: false)
      redirect_to rental_items_path,
                  notice: "L'objet '#{@rental_item.name}' a été supprimé."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :show
    end
  end

  private

  def get_rental_item
    @rental_item = RentalItem.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "rental_items"
    )
    @settings_view = true
  end
end
