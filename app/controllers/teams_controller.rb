class TeamsController < BaseController
    before_action :get_team, only: [:show, :edit, :update, :destroy]
  
    breadcrumb "Pôles", :teams_path, match: :exact
  
    def index
      @teams = TeamDecorator
        .decorate_collection(Team.all.order(name: :asc))
    end
  
    def show
      @team = TeamDecorator.new(@team)
    end
  
    def new
      @team = Team.new
    end
  
    def create
      service = Teams::CreateService.new
      if service.run(params)
        redirect_to team_path(service.team),
                    notice: "Super! Le pôle '#{service.team.name}' a été ajouté."
      else
        @team = service.team
        set_error_flash(service.team, service.error_message)
        render :new
      end
    end
  
    def edit
    end
  
    def update
      service = Teams::UpdateService.new(
        team: Team.find(params[:id])
      )
      if service.run(params)
        redirect_to team_path(service.team),
                    notice: "Le pôle a été mis à jour."
      else
        @team = service.team
        set_error_flash(service.team, service.error_message)
        render :edit
      end
    end
  
    def destroy
      if @team.soft_delete!(validate: false)
        redirect_to teams_path,
                    notice: "Le pôle '#{@team.name}' a été supprimé."
      else
        flash.now[:alert] = "Une erreur est survenue."
        render :show
      end
    end
  
    private
  
    def get_team
      @team = Team.find(params[:id])
    end
  
    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(
        active_primary: "projects",
        active_secondary: "teams"
      )
      @projects_view = true
    end
  end
  