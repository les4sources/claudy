class ExperiencesController < BaseController
  before_action :get_experience, only: [:show, :edit, :update, :destroy]

  breadcrumb "Activités", :experiences_path, match: :exact

  def index
    # Un porteur restreint ne voit QUE ses propres activités (son planning) ;
    # l'admin global voit tout (comportement inchangé).
    scope = restricted_human_id ? Experience.where(human_id: restricted_human_id) : Experience.all
    # Calendrier global MENSUEL des créneaux — borné aux activités du porteur
    # restreint le cas échéant (`?month=YYYY-MM` navigue).
    @global_calendar = Experiences::GlobalMonthCalendar.new(
      month: params[:month],
      human_id: restricted_human_id
    )
    @experiences = ExperienceDecorator
      .decorate_collection(scope.order(name: :asc))
    # Créneaux FUTURS par activité (une requête pour toute la liste).
    @future_slot_counts = ExperienceAvailability
      .where("available_on >= ?", Date.today)
      .where(experience_id: scope.select(:id))
      .group(:experience_id)
      .count
  end

  def show
    # Calendrier MENSUEL des disponibilités — démarre sur le mois en cours ;
    # `?month=YYYY-MM` navigue, y compris dans le passé (l'historique des dispos
    # reste consultable). Le rendu du calendrier vit dans un Turbo Frame, donc
    # poser/retirer un créneau et changer de mois ne recharge jamais la page.
    @calendar = Experiences::MonthCalendar.new(
      experience: @experience,
      month: params[:month]
    )
    # Prochaines réservations (bloc « Réservations » — remplace le récap des
    # disponibilités, doublon du calendrier).
    @upcoming_bookings = ExperienceBooking.active
                                          .joins(:experience_availability)
                                          .where(experience_availabilities: { experience_id: @experience.id })
                                          .where("experience_availabilities.available_on >= ?", Date.today)
                                          .includes(:stay, :experience_availability)
                                          .order("experience_availabilities.available_on ASC, experience_availabilities.starts_at ASC")
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

  # `human_id` de cloisonnement quand le porteur est restreint à ses activités,
  # sinon `nil` (pas de restriction). Fail-closed : un porteur restreint sans
  # `human_id` ne verra aucune activité plutôt que toutes.
  def restricted_human_id
    current_user&.restricted_to_experiences? ? current_user.human_id : nil
  end

  def get_experience
    @experience = Experience.find(params[:id])
    # Un porteur restreint ne peut consulter qu'une de SES activités.
    if restricted_human_id && @experience.human_id != restricted_human_id
      redirect_to experiences_path
    end
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "experiences"
    )
    @settings_view = true
  end
end
