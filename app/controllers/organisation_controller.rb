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
    @cycle_actions = @human.cycle_actions.not_archived.ordered.group_by(&:category)
    @demandees = CycleAction.demandee.not_archived.active.where.not(human_id: @human.id)
    @total_hours = @human.cycle_actions.not_archived.active.where.not(category: :reportee).sum(:hours) || 0
    @current_cycle = Cycle.covering_date(Date.today).first
    @archives_count = @human.cycle_actions.archived.count
    @cycle_active_humans = Human.cycle_active.where.not(id: @human.id).order(:name)
    @gathering_actions = @human.gathering_actions
                                .includes(:gathering)
                                .order(:completed, created_at: :desc)
  end

  def archives
    @human = Human.find(params[:human_id])
    scope = @human.cycle_actions.archived
    scope = scope.where(category: params[:category]) if params[:category].present?
    if params[:q].present?
      q = "%#{params[:q].downcase}%"
      scope = scope.where("LOWER(label) LIKE ?", q)
    end
    if params[:cycle_id].present?
      cycle = Cycle.find_by(id: params[:cycle_id])
      if cycle
        scope = scope.where(archived_at: cycle.start_date.beginning_of_day..cycle.end_date.end_of_day)
      end
    end
    @archived_actions = scope.order(archived_at: :desc).paginate(page: params[:page], per_page: 25)

    archives_all = @human.cycle_actions.archived
    @archives_total = archives_all.count
    @archives_first_at = archives_all.minimum(:archived_at)
    @archives_last_at = archives_all.maximum(:archived_at)
    @archives_per_category = archives_all.group(:category).count

    if @archives_first_at && @archives_last_at
      @available_cycles = Cycle.where(
        "(start_date, end_date) OVERLAPS (?, ?)",
        @archives_first_at.to_date, @archives_last_at.to_date
      ).order(start_date: :desc)
    else
      @available_cycles = []
    end

    @current_category = params[:category]
    @current_cycle_id = params[:cycle_id]
    @current_q = params[:q]
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation"
    )
    @organisation_view = true
  end
end
