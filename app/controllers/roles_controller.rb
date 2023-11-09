class RolesController < BaseController
  before_action :get_role, only: [:show, :edit, :update, :destroy]

  breadcrumb "Rôles", :roles_path, match: :exact

  def index
    @roles = RoleDecorator
      .decorate_collection(Role.all.order(name: :asc))
  end

  def show
    @role = RoleDecorator.new(@role)
  end

  def new
    @role = Role.new
  end

  def create
    service = Roles::CreateService.new
    if service.run(params)
      redirect_to role_path(service.role),
                  notice: "Super! Le rôle '#{service.role.name}' a été ajouté."
    else
      @role = service.role
      set_error_flash(service.role, service.error_message)
      render :new
    end
  end

  def edit
  end

  def update
    service = Roles::UpdateService.new(
      role: Role.find(params[:id])
    )
    if service.run(params)
      redirect_to role_path(service.role),
                  notice: "Le rôle a été mis à jour."
    else
      @role = service.role
      set_error_flash(service.role, service.error_message)
      render :edit,
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def destroy
    if @role.soft_delete!(validate: false)
      redirect_to roles_path,
                  notice: "Le rôle '#{@role.name}' a été supprimé."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :show
    end
  end

  private

  def get_role
    @role = Role.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "roles"
    )
    @settings_view = true
  end
end
