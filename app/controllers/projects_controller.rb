class ProjectsController < BaseController
    before_action :get_project, only: [:show, :edit, :update, :destroy]
  
    breadcrumb "Projets", :projects_path, match: :exact
  
    # Rangés par pôle (Michael, 2026-10-19) ; les projets d'avant, sans pôle,
    # viennent en dernier pour qu'on les rattache.
    def index
      projects = Project.includes(:human, :team).order(name: :asc).to_a
      @projects_by_team = projects
        .group_by(&:team)
        .sort_by { |team, _| team ? [0, team.name.to_s.downcase] : [1, ""] }
        .map { |team, list| [team, ProjectDecorator.decorate_collection(list)] }
    end
  
    def show
      @project = ProjectDecorator.new(@project)
      set_tasks_view
    end
  
    # Depuis la page d'un pôle, le projet naît dans ce pôle, porté par la
    # personne qui le crée ; les deux restent modifiables.
    def new
      @project = Project.new(team_id: params[:team_id], human: current_user&.human)
    end
  
    def create
      service = Projects::CreateService.new
      if service.run(params)
        redirect_to project_path(service.project),
                    notice: "Super! Le projet '#{service.project.name}' a été ajouté."
      else
        @project = service.project
        set_error_flash(service.project, service.error_message)
        render :new
      end
    end
  
    def edit
    end
  
    def update
      service = Projects::UpdateService.new(
        project: Project.find(params[:id])
      )
      if service.run(params)
        redirect_to project_path(service.project),
                    notice: "Le projet a été mis à jour."
      else
        @project = service.project
        set_error_flash(service.project, service.error_message)
        render :edit,
               status: :unprocessable_entity,
               alert: service.error_message
      end
    end
  
    def destroy
      if @project.soft_delete!(validate: false)
        redirect_to projects_path,
                    notice: "Le projet '#{@project.name}' a été supprimé."
      else
        flash.now[:alert] = "Une erreur est survenue."
        render :show
      end
    end
  
    private
  
    def get_project
      @project = Project.find(params[:id])
    end
  
    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(
        active_primary: "projects",
        active_secondary: "projects"
      )
      @projects_view = true
    end

    def set_tasks_view
      case params[:view]
      when "list"
        @tasks_view = "list"
      when "board"
        @tasks_view = "board"
      else
        @tasks_view = "list"
      end
    end
  end
  