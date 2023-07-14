class ExperiencesController < BaseController
  before_action :get_experience, only: [:show, :edit, :update, :destroy]

  breadcrumb "Expériences", :experiences_path, match: :exact

  def index
    @experiences = ExperienceDecorator
      .decorate_collection(Experience.all.order(name: :asc))
  end

  def show
    @experience = ExperienceDecorator.new(@experience)
  end

  def new
    @experience = Experience.new
  end

  def create
    service = Experiences::CreateService.new
    if service.run(params)
      redirect_to experience_path(service.experience),
                  notice: "Super! L'expérience '#{service.experience.name}' a été ajoutée."
    else
      @experience = service.experience
      set_error_flash(service.experience, service.error_message)
      render :new
    end
  end

  def edit
  end

  def update
    service = Experiences::UpdateService.new(
      experience: Experience.find(params[:id])
    )
    if service.run(params)
      redirect_to experience_path(service.experience),
                  notice: "L'expérience a été mise à jour."
    else
      @experience = service.experience
      set_error_flash(service.experience, service.error_message)
      render :edit
    end
  end

  def destroy
    if @experience.soft_delete!(validate: false)
      redirect_to experiences_path,
                  notice: "L'expérience '#{@experience.name}' a été supprimée."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :show
    end
  end

  private

  def get_experience
    @experience = Experience.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "experiences"
    )
    @settings_view = true
  end
end
