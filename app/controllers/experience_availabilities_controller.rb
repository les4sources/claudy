class ExperienceAvailabilitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_experience

  # Dépôt d'un bloc depuis le calendrier hebdo (epic #25, Phase 4) : un clic sur
  # une case suffit — la durée vient de l'activité, le non-chevauchement et les
  # bornes 8h-22h sont validés par le modèle.
  def create
    @availability = @experience.experience_availabilities.build(availability_params)
    if @availability.save
      redirect_to experience_week_path, notice: "Disponibilité ajoutée."
    else
      redirect_to experience_week_path, alert: @availability.errors.full_messages.to_sentence
    end
  end

  def destroy
    @availability = @experience.experience_availabilities.find(params[:id])
    @availability.destroy
    redirect_to experience_week_path, notice: "Disponibilité supprimée."
  end

  private

  def set_experience
    @experience = Experience.find(params[:experience_id])
  end

  # On revient sur la semaine que le porteur regardait, pas sur la semaine
  # courante : sans ça, poser un bloc trois semaines plus loin le ramènerait
  # au début à chaque clic.
  def experience_week_path
    week = params[:week].presence
    week ? experience_path(@experience, week: week) : experience_path(@experience)
  end

  def availability_params
    params.require(:experience_availability).permit(:available_on, :starts_at, :duration_minutes, :max_participants, :notes)
  end
end
