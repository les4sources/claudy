class OrganisationController < BaseController
  breadcrumb "Organisation", :organisation_path, match: :exact

  def index
    @humans = Human.cycle_active.order(:name)
    @cycles = Cycle.chronological
  end

  def member
    @human = Human.find(params[:human_id])
    @cycle_actions = @human.cycle_actions.order(:completed, :created_at).group_by(&:category)
    @demandees = CycleAction.demandee.active.where.not(human_id: @human.id)
    @total_hours = @human.cycle_actions.active.sum(:hours) || 0
    @cycle_active_humans = Human.cycle_active.where.not(id: @human.id).order(:name)
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation"
    )
    @organisation_view = true
  end
end
