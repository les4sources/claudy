class CycleActionsController < BaseController
  before_action :get_cycle_action, only: [:edit, :update, :destroy, :toggle_completed, :defer]

  def create
    service = CycleActions::CreateService.new
    if service.run(params)
      @cycle_action = service.cycle_action
      @human = @cycle_action.human
      @total_hours = @human.cycle_actions.active.sum(:hours) || 0
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to organisation_member_path(@human.id) }
      end
    else
      @cycle_action = service.cycle_action
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "new_cycle_action_form",
            partial: "cycle_actions/form",
            locals: { cycle_action: @cycle_action, human: @cycle_action.human }
          )
        }
        format.html { redirect_to organisation_member_path(params[:cycle_action][:human_id]) }
      end
    end
  end

  def edit
    @human = @cycle_action.human
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "cycle_action_#{@cycle_action.id}",
          partial: "cycle_actions/edit_form",
          locals: { cycle_action: @cycle_action, human: @human }
        )
      }
      format.html { redirect_to organisation_member_path(@human.id) }
    end
  end

  def update
    service = CycleActions::UpdateService.new(cycle_action: @cycle_action)
    if service.run(params)
      @cycle_action = service.cycle_action
      @human = @cycle_action.human
      @total_hours = @human.cycle_actions.active.sum(:hours) || 0
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to organisation_member_path(@human.id) }
      end
    else
      @cycle_action = service.cycle_action
      @human = @cycle_action.human
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "cycle_action_#{@cycle_action.id}",
            partial: "cycle_actions/edit_form",
            locals: { cycle_action: @cycle_action, human: @human }
          )
        }
        format.html { redirect_to organisation_member_path(@human.id) }
      end
    end
  end

  def toggle_completed
    @cycle_action.update!(completed: !@cycle_action.completed)
    @human = @cycle_action.human
    @total_hours = @human.cycle_actions.active.sum(:hours) || 0
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to organisation_member_path(@human.id) }
    end
  end

  def defer
    old_category = @cycle_action.category
    @cycle_action.update!(category: :reportee)
    @human = @cycle_action.human
    @total_hours = @human.cycle_actions.active.sum(:hours) || 0
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.remove("cycle_action_#{@cycle_action.id}"),
          turbo_stream.append(
            "category_reportee_list",
            partial: "cycle_actions/cycle_action",
            locals: { cycle_action: @cycle_action }
          ),
          turbo_stream.replace(
            "hours_total",
            partial: "cycle_actions/hours_total",
            locals: { total_hours: @total_hours }
          ),
          turbo_stream.replace(
            "category_#{old_category}_count",
            partial: "cycle_actions/category_count",
            locals: { category: old_category, count: @human.cycle_actions.active.where(category: old_category).count }
          ),
          turbo_stream.replace(
            "category_reportee_count",
            partial: "cycle_actions/category_count",
            locals: { category: "reportee", count: @human.cycle_actions.active.where(category: :reportee).count }
          )
        ]
      }
      format.html { redirect_to organisation_member_path(@human.id) }
    end
  end

  def destroy
    @human = @cycle_action.human
    category = @cycle_action.category
    @cycle_action.soft_delete!(validate: false)
    @total_hours = @human.cycle_actions.active.sum(:hours) || 0
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.remove("cycle_action_#{@cycle_action.id}"),
          turbo_stream.replace(
            "hours_total",
            partial: "cycle_actions/hours_total",
            locals: { total_hours: @total_hours }
          ),
          turbo_stream.replace(
            "category_#{category}_count",
            partial: "cycle_actions/category_count",
            locals: { category: category, count: @human.cycle_actions.active.where(category: category).count }
          )
        ]
      }
      format.html { redirect_to organisation_member_path(@human.id) }
    end
  end

  private

  def get_cycle_action
    @cycle_action = CycleAction.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation"
    )
    @organisation_view = true
  end
end
