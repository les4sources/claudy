class HumansController < BaseController
  before_action :get_human, only: [:show, :edit, :update, :destroy]

  breadcrumb "Équipe", :humans_path, match: :exact

  def index
    @humans = HumanDecorator
      .decorate_collection(Human.unscoped.all.order(name: :asc))
  end

  def show
  end

  def new
    @human = Human.new
  end

  def create
    service = Humans::CreateService.new
    if service.run(params)
      redirect_to human_path(service.human),
                  notice: "Super! #{service.human.name} a été ajouté à l'équipe."
    else
      @human = service.human
      set_error_flash(service.human, service.error_message)
      render :new
    end
  end

  def edit
  end

  def update
    service = Humans::UpdateService.new(
      human: Human.find(params[:id])
    )
    if service.run(params)
      redirect_to human_path(service.human),
                  notice: "Le membre de l'équipe a été mis à jour."
    else
      @human = service.human
      set_error_flash(service.human, service.error_message)
      render :edit,
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def destroy
    if @human.soft_delete!(validate: false)
      redirect_to humans_path,
                  notice: "#{@human.name} a été supprimé de l'équipe."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :show
    end
  end

  private

  def get_human
    @human = Human.unscoped.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "humans"
    )
    @settings_view = true
  end
end
