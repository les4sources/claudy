class OrganisationController < BaseController
  include CycleLoadHelper

  breadcrumb "Organisation", :organisation_path, match: :exact

  def index
    humans = Human.cycle_active.order(:name).to_a
    @current_cycle = Cycle.covering_date(Date.today).first
    @cycles = Cycle.chronological

    # Bulk-load category hours and action counts per human (no N+1).
    human_ids = humans.map(&:id)
    hours_by_human_category = CycleAction.active.where(human_id: human_ids)
                                         .group(:human_id, :category)
                                         .sum(:hours)
    counts_by_human_category = CycleAction.active.where(human_id: human_ids)
                                          .group(:human_id, :category)
                                          .count

    @member_loads = humans.map do |human|
      cat_hours = {}
      cat_counts = {}
      CycleAction.categories.each_key do |name|
        cat_hours[name] = (hours_by_human_category[[human.id, name]] || 0).to_f
        cat_counts[name] = counts_by_human_category[[human.id, name]] || 0
      end
      engaged = cat_hours.except("reportee").values.sum
      total_actions = cat_counts.values.sum
      reportee_count = cat_counts["reportee"]
      load = cycle_load_for(engaged: engaged, cycle: @current_cycle)
      pace = cycle_weekly_pace(engaged: engaged, cycle: @current_cycle)
      {
        human: human,
        engaged: engaged,
        total_actions: total_actions,
        reportee_count: reportee_count,
        cat_hours: cat_hours,
        cat_counts: cat_counts,
        load: load,
        pace: pace,
      }
    end

    # Sort by load desc (overloaded first), then by engaged hours desc.
    @member_loads.sort_by! { |m| [-m[:load][:ratio], -m[:engaged]] }

    # Team aggregate
    total_engaged = @member_loads.sum { |m| m[:engaged] }
    total_available = @member_loads.sum { |m| m[:load][:available] }
    @team_load = {
      engaged: total_engaged,
      available: total_available,
      ratio: total_available > 0 ? total_engaged / total_available : 0,
      member_count: @member_loads.size,
      overloaded: @member_loads.count { |m| m[:load][:state] == :overload },
      idle: @member_loads.count { |m| m[:load][:state] == :idle },
    }

    @humans = humans
    next_g = Gathering.upcoming.includes(:gathering_category, :agenda_items).first
    @next_gathering = next_g ? GatheringDecorator.new(next_g) : nil
    @recent_decisions = DecisionDecorator.decorate_collection(
      Decision.recent.includes(:recorded_by, :gathering).limit(4)
    )
  end

  def member
    @human = Human.find(params[:human_id])
    @cycle_actions = @human.cycle_actions.ordered.group_by(&:category)
    @demandees = CycleAction.demandee.active.where.not(human_id: @human.id)
    @total_hours = @human.cycle_actions.active.where.not(category: :reportee).sum(:hours) || 0
    @current_cycle = Cycle.covering_date(Date.today).first
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
