class ExperiencesController < BaseController
  before_action :get_experience, only: [:show, :edit, :update, :destroy]

  breadcrumb "Activités", :experiences_path, match: :exact

  def index
    @experiences = ExperienceDecorator
      .decorate_collection(Experience.all.order(name: :asc))
  end

  def show
    # Calendrier hebdo des disponibilités (epic #25, Phase 4) — démarre sur la
    # semaine en cours ; `?week=` permet de naviguer, y compris dans le passé
    # (l'historique des dispos reste consultable).
    @week_calendar = Experiences::WeekCalendar.new(
      experience: @experience,
      week_start: (Date.parse(params[:week]) rescue nil)
    )
    @experience = ExperienceDecorator.new(@experience)
  end

  def new
    @experience = Experience.new
  end

  def create
    service = Experiences::CreateService.new
    if service.run(params)
      redirect_to experience_path(service.experience),
                  notice: "Super! L'activité '#{service.experience.name}' a été ajoutée."
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
                  notice: "L'activité a été mise à jour."
    else
      @experience = service.experience
      set_error_flash(service.experience, service.error_message)
      render :edit, 
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def destroy
    if @experience.soft_delete!(validate: false)
      redirect_to experiences_path,
                  notice: "L'activité '#{@experience.name}' a été supprimée."
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
