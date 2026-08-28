class CycleActionsController < BaseController
  before_action :get_cycle_action, only: [:edit, :update, :destroy, :toggle_completed, :defer, :defer_next, :undo_defer_next, :settle, :archive, :unarchive]
  before_action :ensure_open_cycle, only: [:edit, :update, :destroy, :toggle_completed, :defer, :defer_next, :settle, :archive, :unarchive]

  def create
    service = CycleActions::CreateService.new
    if service.run(params)
      @cycle_action = service.cycle_action
      @human = @cycle_action.human
      @cycle = @cycle_action.cycle
      @total_hours = engaged_hours
      @category_actions = live_scope.where(category: @cycle_action.category).ordered
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to member_path }
      end
    else
      @cycle_action = service.cycle_action
      @cycle = @cycle_action.cycle
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "new_cycle_action_form",
            partial: "cycle_actions/form",
            locals: { cycle_action: @cycle_action, human: @cycle_action.human, cycle: @cycle }
          )
        }
        format.html { redirect_to organisation_member_path(params[:cycle_action][:human_id], cycle_id: params.dig(:cycle_action, :cycle_id)) }
      end
    end
  end

  def edit
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "cycle_action_#{@cycle_action.id}",
          partial: "cycle_actions/edit_form",
          locals: { cycle_action: @cycle_action, human: @human }
        )
      }
      format.html { redirect_to member_path }
    end
  end

  def update
    @old_category = @cycle_action.category
    service = CycleActions::UpdateService.new(cycle_action: @cycle_action)
    if service.run(params)
      @cycle_action = service.cycle_action
      @total_hours = engaged_hours
      @category_actions = live_scope.where(category: @cycle_action.category).ordered
      @old_category_actions = live_scope.where(category: @old_category).ordered if @old_category != @cycle_action.category
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to member_path }
      end
    else
      @cycle_action = service.cycle_action
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "cycle_action_#{@cycle_action.id}",
            partial: "cycle_actions/edit_form",
            locals: { cycle_action: @cycle_action, human: @human }
          )
        }
        format.html { redirect_to member_path }
      end
    end
  end

  def toggle_completed
    @cycle_action.update!(completed: !@cycle_action.completed)
    @total_hours = engaged_hours
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to member_path }
    end
  end

  # Met l'action dans le sas « reportée » du cycle courant (elle sort du
  # comptage des heures). Le passage effectif au cycle suivant se fait avec
  # `defer_next` ou à la clôture.
  def defer
    old_category = @cycle_action.category
    @cycle_action.update!(category: :reportee)
    @total_hours = engaged_hours
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          replace_list(old_category),
          replace_list("reportee"),
          replace_hours_total,
          replace_count(old_category),
          replace_count("reportee")
        ]
      }
      format.html { redirect_to member_path }
    end
  end

  # Passe l'action au cycle suivant : copie liée là-bas, issue « reportée » ici.
  def defer_next
    service = CycleActions::DeferService.new(cycle_action: @cycle_action)
    if service.run
      @total_hours = engaged_hours
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: [
            turbo_stream.remove("cycle_action_#{@cycle_action.id}"),
            replace_hours_total,
            replace_count(@cycle_action.category),
            turbo_stream.append(
              "flash_toasts",
              partial: "cycle_actions/deferred_toast",
              locals: { cycle_action: @cycle_action, target_cycle: service.target_cycle }
            )
          ]
        }
        format.html { redirect_to member_path, notice: "Action passée au cycle « #{service.target_cycle.name} »." }
      end
    else
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.append(
            "flash_toasts",
            partial: "cycle_actions/error_toast",
            locals: { message: service.error_message, cycle: @cycle }
          )
        }
        format.html { redirect_to member_path, alert: service.error_message }
      end
    end
  end

  # Annule un passage au cycle suivant : supprime la copie, rouvre l'origine.
  def undo_defer_next
    copy = @cycle_action.deferred_to
    CycleAction.transaction do
      copy&.soft_delete!(validate: false)
      @cycle_action.update!(outcome: nil)
    end
    redirect_to member_path, notice: "Action ramenée dans ce cycle."
  end

  # Triage depuis la page de clôture : fait / suivant / archiver.
  def settle
    case params[:as]
    when "done"
      @cycle_action.update!(completed: true)
    when "next"
      service = CycleActions::DeferService.new(cycle_action: @cycle_action)
      unless service.run
        redirect_to closing_cycle_path(@cycle), alert: service.error_message
        return
      end
    when "drop"
      @cycle_action.archive!
    end
    respond_to do |format|
      format.turbo_stream {
        report = Cycles::MemberReport.new(human: @human, cycle: @cycle)
        render turbo_stream: turbo_stream.replace(
          "closing_member_#{@human.id}",
          partial: "cycles/closing_member",
          locals: { report: report, next_cycle: @cycle.next_cycle }
        )
      }
      format.html { redirect_to closing_cycle_path(@cycle) }
    end
  end

  def archive
    @cycle_action.archive!
    @total_hours = engaged_hours
    archives_count = @human.cycle_actions.archived.count
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.remove("cycle_action_#{@cycle_action.id}"),
          replace_hours_total,
          replace_count(@cycle_action.category),
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
      format.html { redirect_to member_path, notice: "Action archivée." }
    end
  end

  def unarchive
    @cycle_action.unarchive!
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.remove("archived_row_#{@cycle_action.id}")
      }
      format.html { redirect_to member_path, notice: "Action restaurée." }
    end
  end

  def archive_completed
    human = Human.find(params[:human_id])
    cycle = Cycle.find(params[:cycle_id])
    scope = human.cycle_actions.for_cycle(cycle).live.where(completed: true)
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope.update_all(archived_at: Time.current, outcome: CycleAction.outcomes[:done])
    redirect_to organisation_member_path(human.id, cycle_id: cycle.id), notice: "Actions cochées archivées."
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
    category = @cycle_action.category
    @cycle_action.soft_delete!(validate: false)
    @total_hours = engaged_hours
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.remove("cycle_action_#{@cycle_action.id}"),
          replace_hours_total,
          replace_count(category)
        ]
      }
      format.html { redirect_to member_path }
    end
  end

  private

  def get_cycle_action
    @cycle_action = CycleAction.find(params[:id])
    @human = @cycle_action.human
    @cycle = @cycle_action.cycle
  end

  def ensure_open_cycle
    return if @cycle.open?
    message = "Ce cycle est clos : ses actions ne se modifient plus."
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.append(
          "flash_toasts",
          partial: "cycle_actions/error_toast",
          locals: { message: message, cycle: @cycle }
        )
      }
      format.html { redirect_to member_path, alert: message }
    end
  end

  def member_path
    organisation_member_path(@human.id, cycle_id: @cycle&.id)
  end

  def live_scope
    @human.cycle_actions.for_cycle(@cycle).live
  end

  def engaged_hours
    live_scope.active.engaged.sum(:hours) || 0
  end

  def replace_list(category)
    turbo_stream.replace(
      "category_#{category}_list",
      partial: "cycle_actions/sorted_list",
      locals: { actions: live_scope.where(category: category).ordered, category: category.to_s, human: @human }
    )
  end

  def replace_count(category)
    scope = live_scope.active.where(category: category)
    turbo_stream.replace(
      "category_#{category}_count",
      partial: "cycle_actions/category_count",
      locals: { category: category.to_s, count: scope.count, hours: scope.sum(:hours) }
    )
  end

  def replace_hours_total
    turbo_stream.replace(
      "hours_total",
      partial: "cycle_actions/hours_total",
      locals: { total_hours: @total_hours, human: @human, cycle: @cycle }
    )
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation"
    )
    @organisation_view = true
  end
end
