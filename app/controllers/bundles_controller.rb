class BundlesController < BaseController
    before_action :get_bundle, only: [:edit, :update, :destroy]
  
    breadcrumb "Actions", :tasks_path, match: :exact
  
    def new
      @bundle = Bundle.new(
        project_id: params[:project_id],
        team: params[:team_id]
      )
    end
  
    def create
      service = Bundles::CreateService.new
      if service.run(params)
        redirect_to redirect_path_for(service.bundle),
                    notice: "Super! Le groupe a été ajouté."
      else
        @bundle = service.bundle
        set_error_flash(service.bundle, service.error_message)
        render :new
      end
    end
  
    def edit
    end
  
    def update
      service = Bundles::UpdateService.new(
        bundle: Bundle.find(params[:id])
      )
      if service.run(params)
        redirect_to redirect_path_for(service.bundle),
                    notice: "Le groupe a été mis à jour."
      else
        @bundle = service.bundle
        set_error_flash(service.bundle, service.error_message)
        render :edit
      end
    end
  
    def destroy
      if @bundle.soft_delete!(validate: false)
        redirect_to redirect_path_for(bundle),
                    notice: "Le groupe '#{@bundle.name}' a été supprimé."
      else
        flash.now[:alert] = "Une erreur est survenue."
        render :show
      end
    end
  
    private
  
    def get_bundle
      @bundle = Bundle.find(params[:id])
    end

    def redirect_path_for(bundle)
      !bundle.project.nil? ? project_path(bundle.project) : team_path(bundle.team)
    end
  
    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(
        active_primary: "projects",
        active_secondary: "tasks"
      )
      @projects_view = true
    end
  end
  