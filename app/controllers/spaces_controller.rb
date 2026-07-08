class SpacesController < BaseController
  before_action :get_space, only: [:show, :edit, :update, :destroy]

  breadcrumb "Espaces", :spaces_path, match: :exact

  def index
    @spaces = SpaceDecorator
      .decorate_collection(Space.all.order(position: :asc))
  end

  def show
    @space = SpaceDecorator.new(@space)
  end

  def new
    @space = Space.new
  end

  def create
    service = Spaces::CreateService.new
    if service.run(params)
      redirect_to space_path(service.space),
                  notice: "Super! L'espace '#{service.space.name}' a été ajouté."
    else
      @space = service.space
      set_error_flash(service.space, service.error_message)
      render :new
    end
  end

  def edit
  end

  def update
    service = Spaces::UpdateService.new(
      space: Space.find(params[:id])
    )
    if service.run(params)
      redirect_to space_path(service.space),
                  notice: "L'espace a été mis à jour."
    else
      @space = service.space
      set_error_flash(service.space, service.error_message)
      render :edit,
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def destroy
    if @space.soft_delete!(validate: false)
      redirect_to spaces_path,
                  notice: "L'espace '#{@space.name}' a été supprimé."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :show
    end
  end

  private

  def get_space
    @space = Space.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "spaces"
    )
    @settings_view = true
  end
end
