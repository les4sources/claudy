class OrganisationController < BaseController
  breadcrumb "Organisation", :organisation_path, match: :exact

  def index
    @humans = Human.cycle_active.order(:name)
    @cycles = Cycle.chronological
    next_g = Gathering.upcoming.includes(:gathering_category, :agenda_items).first
    @next_gathering = next_g ? GatheringDecorator.new(next_g) : nil
    @recent_decisions = DecisionDecorator.decorate_collection(
      Decision.recent.includes(:recorded_by, :gathering).limit(4)
    )
  end

  def member
    @human = Human.find(params[:human_id])
    @cycle_actions = @human.cycle_actions.order(:completed, Arel.sql("COALESCE(hours, 0) DESC"), :created_at).group_by(&:category)
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
