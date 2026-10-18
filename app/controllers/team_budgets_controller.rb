# Le budget annuel d'un pôle (Michael, 2026-10-18) : deux montants par année
# civile, saisis depuis la page du pôle et relus en tête de celle-ci.
class TeamBudgetsController < BaseController
  before_action :get_team_and_budget

  # Un budget neuf part du réel de l'année d'avant : on corrige des chiffres
  # plutôt que de les inventer. Le formulaire le dit.
  def edit
    if detailed?
      return redirect_to team_path(@team, year: @budget.year),
                         notice: "Le budget #{@budget.year} de ce pôle est détaillé : il se modifie dans Comptabilité › Budget."
    end

    breadcrumb "Pôles", :organisation_teams_path
    breadcrumb @team.name, team_path(@team, year: @budget.year)
    return unless @budget.new_record?

    @reference = Teams::Accounts.new(team: @team, year: @budget.year - 1).own_totals
    @budget.revenue_cents = @reference.revenue_cents.clamp(0, nil)
    @budget.expense_cents = @reference.expense_cents.clamp(0, nil)
  end

  def update
    @budget.assign_attributes(budget_params)
    if @budget.save
      redirect_to team_path(@team, year: @budget.year), notice: "Budget #{@budget.year} du pôle enregistré."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # Les lignes du budget détaillé priment : deux montants saisis ici seraient
  # ignorés par la page du pôle.
  def detailed? = @team.budget_lines.for_year(@budget.year).exists?

  def get_team_and_budget
    @team = Team.find(params[:team_id])
    year = params[:id].to_i
    raise ActiveRecord::RecordNotFound unless (2000..2100).cover?(year)

    @budget = @team.team_budgets.find_or_initialize_by(year: year)
  end

  def budget_params
    params.require(:team_budget).permit(:revenue, :expense, :notes)
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation",
      active_secondary: "teams"
    )
    @organisation_view = true
  end
end
