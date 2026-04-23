class DecisionsController < BaseController
  before_action :set_decision, only: [:show, :edit, :update, :destroy]

  breadcrumb "Organisation", :organisation_path, match: :exact
  breadcrumb "Registre des décisions", :organisation_decisions_path, match: :exact

  def index
    @query = params[:q].to_s.strip
    @decisions = DecisionDecorator.decorate_collection(
      Decision.search(@query).recent.includes(:recorded_by, :gathering)
    )
  end

  def show
    @decision = DecisionDecorator.new(@decision)
  end

  def new
    gathering = Gathering.find_by(id: params[:gathering_id]) if params[:gathering_id].present?
    agenda_item = AgendaItem.find_by(id: params[:agenda_item_id]) if params[:agenda_item_id].present?
    @decision = Decision.new(
      gathering: gathering,
      agenda_item: agenda_item,
      taken_at: gathering&.starts_at&.to_date || Date.today
    )
  end

  def create
    service = Decisions::CreateService.new(recorded_by: current_human)
    if service.run(params)
      redirect_to decision_path(service.decision),
                  notice: "La décision a été consignée."
    else
      @decision = service.decision
      set_error_flash(service.decision, service.error_message)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    service = Decisions::UpdateService.new(decision: @decision)
    if service.run(params)
      redirect_to decision_path(service.decision),
                  notice: "La décision a été mise à jour."
    else
      @decision = service.decision
      set_error_flash(service.decision, service.error_message)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @decision.soft_delete!(validate: false)
    redirect_to organisation_decisions_path,
                status: :see_other,
                notice: "La décision a été supprimée."
  end

  private

  def set_decision
    @decision = Decision.find(params[:id])
  end

  def current_human
    current_user&.human || Human.where(status: "active").first
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "organisation",
      active_secondary: "decisions"
    )
  end
end
