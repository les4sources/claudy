class ServicesController < BaseController
  before_action :get_service, only: [:show, :edit, :update, :destroy]

  breadcrumb "Services", :services_path, match: :exact

  def index
    @services = ServiceDecorator
      .decorate_collection(Service.all.order(name: :asc))
  end

  def show
    @service = ServiceDecorator.new(@service)
  end

  def new
    @service = Service.new
  end

  def create
    service = Services::CreateService.new
    if service.run(params)
      redirect_to service_path(service.service),
                  notice: "Super! Le service '#{service.service.name}' a été ajouté."
    else
      @service = service.service
      set_error_flash(service.service, service.error_message)
      render :new
    end
  end

  def edit
  end

  def update
    service = Services::UpdateService.new(
      service: Service.find(params[:id])
    )
    if service.run(params)
      redirect_to service_path(service.service),
                  notice: "Le service a été mise à jour."
    else
      @service = service.service
      set_error_flash(service.service, service.error_message)
      render :edit
    end
  end

  def destroy
    if @service.soft_delete!(validate: false)
      redirect_to services_path,
                  notice: "Le service '#{@service.name}' a été supprimé."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :show
    end
  end

  private

  def get_service
    @service = Service.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "services"
    )
    @settings_view = true
  end
end
