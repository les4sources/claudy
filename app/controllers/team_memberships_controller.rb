# Les membres d'un pôle (epic #239, phase 1). Trois gestes — ajouter, changer
# de rôle, retirer — et une seule réponse : le bloc « Membres » de l'écran
# d'édition, remplacé en Turbo Stream. La page ne se recharge jamais.
#
# On ne détruit pas une adhésion, on la soft-delete : l'historique de qui a
# porté quel pôle a de la valeur, et PaperTrail le garde.
class TeamMembershipsController < BaseController
  before_action :get_team
  before_action :get_membership, only: %i[update destroy]

  def create
    @membership = @team.team_memberships.build(membership_params)

    if @membership.save
      @membership = nil
      render_members
    else
      render_members(status: :unprocessable_entity)
    end
  end

  def update
    @membership.update(membership_params.slice(:role))
    render_members(status: @membership.errors.any? ? :unprocessable_entity : :ok)
  end

  def destroy
    @membership.soft_delete!(validate: false)
    @membership = nil
    render_members
  end

  private

  def get_team = @team = Team.find(params[:team_id])

  def get_membership = @membership = @team.team_memberships.find(params[:id])

  def membership_params
    params.require(:team_membership).permit(:human_id, :role)
  end

  # Le bloc entier, remplacé sur place. Sans Turbo, on retombe sur l'écran
  # d'édition : les trois gestes restent utilisables.
  def render_members(status: :ok)
    @memberships = @team.team_memberships.includes(:human).sort_by { |m| m.human.name.to_s }
    @addable_humans = Human.ordered_addable_to(@team)
    @membership ||= TeamMembership.new(team: @team, role: "member")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "team-members",
          partial: "teams/members",
          locals: { team: @team, memberships: @memberships,
                    addable_humans: @addable_humans, membership: @membership }
        ), status: status
      end
      format.html { redirect_to edit_team_path(@team) }
    end
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "teams"
    )
    @settings_view = true
  end
end
