class TeamsController < BaseController
    before_action :get_team, only: [:show, :edit, :update, :destroy]
  
    breadcrumb "Pôles", :teams_path, match: :exact
  
    # Les pôles racines d'abord, chacun suivi de ses enfants : la hiérarchie à
    # deux niveaux se lit dans l'ordre de la liste, sans arborescence à replier.
    def index
      teams = Team.includes(:parent, :children, team_memberships: :human).ordered
      roots, orphans = teams.partition { |team| team.parent_id.nil? }
      @rows = roots.flat_map { |root| [root] + teams.select { |t| t.parent_id == root.id } }
      # Filet : un pôle dont le parent a disparu ne doit pas disparaître avec lui.
      @rows += orphans.reject { |team| @rows.include?(team) }
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
      load_membership_form
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
        render :edit,
               status: :unprocessable_entity,
               alert: service.error_message
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

    # Ce que le bloc « Membres » de l'écran d'édition a besoin de savoir : les
    # adhésions en place, et les humains actifs qu'on peut encore ajouter.
    def load_membership_form
      @memberships = @team.team_memberships.includes(:human).sort_by { |m| m.human.name.to_s }
      @addable_humans = Human.ordered_addable_to(@team)
      @membership ||= TeamMembership.new(team: @team, role: "member")
    end
  
    # Les pôles se CONFIGURENT dans les Paramètres (epic #239, décision 1). La
    # page du pôle passera sous Organisation en phase 3 ; d'ici là, `show`
    # reste dans la même section que le reste du CRUD.
    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(
        active_primary: "settings",
        active_secondary: "teams"
      )
      @settings_view = true
    end
  end
  