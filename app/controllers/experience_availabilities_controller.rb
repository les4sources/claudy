class ExperienceAvailabilitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_experience

  # Dépôt d'un bloc depuis le calendrier mensuel : un clic sur une case suffit —
  # la durée vient de l'activité, le non-chevauchement et les bornes 8h-22h sont
  # validés par le modèle. Réponse en turbo_stream (le frame + le récap latéral
  # se remplacent en place, la position de scroll est conservée) avec repli HTML
  # (redirect) pour le no-JS.
  def create
    @availability = @experience.experience_availabilities.build(availability_params)
    if @availability.save
      @calendar = build_month_calendar
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to experience_month_path, notice: "Disponibilité ajoutée." }
      end
    else
      # Sur échec (chevauchement, hors bornes…) on repasse par un redirect qui
      # porte le flash : Turbo suit la redirection et recharge le frame. Rare, et
      # ça garde le message d'erreur visible.
      redirect_to experience_month_path, alert: @availability.errors.full_messages.to_sentence
    end
  end

  def destroy
    @availability = @experience.experience_availabilities.find(params[:id])
    @availability.destroy
    @calendar = build_month_calendar
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to experience_month_path, notice: "Disponibilité supprimée." }
    end
  end

  private

  def set_experience
    @experience = Experience.find(params[:experience_id])
    # Ce contrôleur n'hérite pas de BaseController : on applique ici le même
    # cloisonnement qu'ailleurs pour un porteur restreint (il ne pose/retire de
    # créneaux que sur SES propres activités).
    if current_user&.restricted_to_experiences? &&
       @experience.human_id != current_user.human_id
      redirect_to experiences_path and return
    end
  end

  # Grille du mois que le porteur regardait (pas le mois courant) : sans ça,
  # poser un bloc deux mois plus loin ramènerait au mois en cours à chaque clic.
  def build_month_calendar
    Experiences::MonthCalendar.new(experience: @experience, month: params[:month])
  end

  def experience_month_path
    month = params[:month].presence
    month ? experience_path(@experience, month: month) : experience_path(@experience)
  end

  def availability_params
    params.require(:experience_availability).permit(:available_on, :starts_at, :duration_minutes, :max_participants, :notes)
  end
end
