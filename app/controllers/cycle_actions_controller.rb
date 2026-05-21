class CycleActionsController < BaseController
  before_action :get_cycle_action, only: [:edit, :update, :destroy, :toggle_completed, :defer, :archive, :unarchive]

  def create
    service = CycleActions::CreateService.new
    if service.run(params)
      @cycle_action = service.cycle_action
      @human = @cycle_action.human
      @total_hours = @human.cycle_actions.not_archived.active.where.not(category: :reportee).sum(:hours) || 0
      @category_actions = @human.cycle_actions.not_archived.where(category: @cycle_action.category).ordered
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
    @old_category = @cycle_action.category
    service = CycleActions::UpdateService.new(cycle_action: @cycle_action)
    if service.run(params)
      @cycle_action = service.cycle_action
      @human = @cycle_action.human
      @total_hours = @human.cycle_actions.not_archived.active.where.not(category: :reportee).sum(:hours) || 0
      @category_actions = @human.cycle_actions.not_archived.where(category: @cycle_action.category).ordered
      @old_category_actions = @human.cycle_actions.not_archived.where(category: @old_category).ordered if @old_category != @cycle_action.category
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
    @total_hours = @human.cycle_actions.not_archived.active.where.not(category: :reportee).sum(:hours) || 0
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to organisation_member_path(@human.id) }
    end
  end

  def defer
    old_category = @cycle_action.category
    @cycle_action.update!(category: :reportee)
    @human = @cycle_action.human
    @total_hours = @human.cycle_actions.not_archived.active.where.not(category: :reportee).sum(:hours) || 0
    reportee_actions = @human.cycle_actions.not_archived.where(category: :reportee).ordered
    old_category_actions = @human.cycle_actions.not_archived.where(category: old_category).ordered
    old_scope = @human.cycle_actions.not_archived.active.where(category: old_category)
    reportee_scope = @human.cycle_actions.not_archived.active.where(category: :reportee)
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.replace(
            "category_#{old_category}_list",
            partial: "cycle_actions/sorted_list",
            locals: { actions: old_category_actions, category: old_category, human: @human }
          ),
          turbo_stream.replace(
            "category_reportee_list",
            partial: "cycle_actions/sorted_list",
            locals: { actions: reportee_actions, category: "reportee", human: @human }
          ),
          turbo_stream.replace(
            "hours_total",
            partial: "cycle_actions/hours_total",
            locals: { total_hours: @total_hours, human: @human }
          ),
          turbo_stream.replace(
            "category_#{old_category}_count",
            partial: "cycle_actions/category_count",
            locals: { category: old_category, count: old_scope.count, hours: old_scope.sum(:hours) }
          ),
          turbo_stream.replace(
            "category_reportee_count",
            partial: "cycle_actions/category_count",
            locals: { category: "reportee", count: reportee_scope.count, hours: reportee_scope.sum(:hours) }
          )
        ]
      }
      format.html { redirect_to organisation_member_path(@human.id) }
    end
  end

  def archive
    @cycle_action.archive!
    @human = @cycle_action.human
    @total_hours = @human.cycle_actions.not_archived.active.where.not(category: :reportee).sum(:hours) || 0
    cat_scope = @human.cycle_actions.not_archived.active.where(category: @cycle_action.category)
    archives_count = @human.cycle_actions.archived.count
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.remove("cycle_action_#{@cycle_action.id}"),
          turbo_stream.replace(
            "hours_total",
            partial: "cycle_actions/hours_total",
            locals: { total_hours: @total_hours, human: @human }
          ),
          turbo_stream.replace(
            "category_#{@cycle_action.category}_count",
            partial: "cycle_actions/category_count",
            locals: { category: @cycle_action.category, count: cat_scope.count, hours: cat_scope.sum(:hours) }
          ),
          turbo_stream.replace(
            "archives_link",
            partial: "organisation/archives_link",
            locals: { human: @human, count: archives_count }
          ),
          turbo_stream.append(
            "flash_toasts",
            partial: "cycle_actions/undo_toast",
            locals: { cycle_action: @cycle_action }
          )
        ]
      }
      format.html { redirect_to organisation_member_path(@human.id), notice: "Action archivée." }
    end
  end

  def unarchive
    @cycle_action.unarchive!
    @human = @cycle_action.human
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.remove("archived_row_#{@cycle_action.id}")
      }
      format.html { redirect_to organisation_member_path(@human.id), notice: "Action restaurée." }
    end
  end

  def archive_completed
    human = Human.find(params[:human_id])
    scope = human.cycle_actions.not_archived.where(completed: true)
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope.update_all(archived_at: Time.current)
    redirect_to organisation_member_path(human.id), notice: "Actions cochées archivées."
  end

  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    category = params[:category]
    human = Human.find(params[:human_id])
    actions = human.cycle_actions.where(id: ids).index_by(&:id)
    CycleAction.transaction do
      ids.each_with_index do |id, idx|
        action = actions[id]
        next unless action
        action.update_columns(position: idx, category: CycleAction.categories[category])
      end
    end
    head :no_content
  end

  def destroy
    @human = @cycle_action.human
    category = @cycle_action.category
    @cycle_action.soft_delete!(validate: false)
    @total_hours = @human.cycle_actions.not_archived.active.where.not(category: :reportee).sum(:hours) || 0
    cat_scope = @human.cycle_actions.not_archived.active.where(category: category)
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.remove("cycle_action_#{@cycle_action.id}"),
          turbo_stream.replace(
            "hours_total",
            partial: "cycle_actions/hours_total",
            locals: { total_hours: @total_hours, human: @human }
          ),
          turbo_stream.replace(
            "category_#{category}_count",
            partial: "cycle_actions/category_count",
            locals: { category: category, count: cat_scope.count, hours: cat_scope.sum(:hours) }
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
