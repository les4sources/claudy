class OrganisationController < BaseController
  include CycleLoadHelper

  breadcrumb "Organisation", :organisation_path, match: :exact

  def index
    humans = Human.cycle_active.roles_enabled.order(:name).to_a
    @current_cycle = Cycle.reference_for
    @cycles = Cycle.chronological

    # Charge par membre, scopée au cycle de référence (no N+1).
    human_ids = humans.map(&:id)
    base = CycleAction.live.active.where(human_id: human_ids)
    base = @current_cycle ? base.for_cycle(@current_cycle) : base.none
    hours_by_human_category = base.group(:human_id, :category).sum(:hours)
    counts_by_human_category = base.group(:human_id, :category).count

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
    @cycle = params[:cycle_id].present? ? Cycle.find(params[:cycle_id]) : Cycle.reference_for
    @current_cycle = @cycle

    if @cycle
      live = @human.cycle_actions.for_cycle(@cycle).live
      @cycle_actions = live.ordered.group_by(&:category)
      @settled_actions = @human.cycle_actions.for_cycle(@cycle).settled.includes(:deferred_to).order(:category, :position)
      # Cycle ouvert : les archivées ont déjà leur page, on ne montre que les reportées.
      @settled_actions = @settled_actions.not_archived if @cycle.open?
      @demandees = CycleAction.for_cycle(@cycle).demandee.live.active.where.not(human_id: @human.id).includes(:human)
      @total_hours = live.active.engaged.sum(:hours) || 0
      @next_cycle = @cycle.next_cycle
      @previous_cycle = @cycle.previous_cycle
      @report = Cycles::MemberReport.new(human: @human, cycle: @cycle)
    else
      @cycle_actions = {}
      @settled_actions = CycleAction.none
      @demandees = CycleAction.none
      @total_hours = 0
    end

    @archives_count = @human.cycle_actions.archived.count
    @cycle_active_humans = Human.cycle_active.roles_enabled.where.not(id: @human.id).order(:name)
    @gathering_actions = @human.gathering_actions
                                .includes(:gathering)
                                .order(:completed, created_at: :desc)
  end

  def archives
    @human = Human.find(params[:human_id])
    scope = @human.cycle_actions.archived.includes(:cycle)
    scope = scope.where(category: params[:category]) if params[:category].present?
    if params[:q].present?
      q = "%#{params[:q].downcase}%"
      scope = scope.where("LOWER(label) LIKE ?", q)
    end
    scope = scope.where(cycle_id: params[:cycle_id]) if params[:cycle_id].present?
    @archived_actions = scope.order(archived_at: :desc).paginate(page: params[:page], per_page: 25)

    archives_all = @human.cycle_actions.archived
    @archives_total = archives_all.count
    @archives_first_at = archives_all.minimum(:archived_at)
    @archives_last_at = archives_all.maximum(:archived_at)
    @archives_per_category = archives_all.group(:category).count
    @available_cycles = Cycle.where(id: archives_all.select(:cycle_id)).order(start_date: :desc)

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
