class ExperienceAvailabilitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_experience

  def create
    @availability = @experience.experience_availabilities.build(availability_params)
    if @availability.save
      redirect_to @experience, notice: "Disponibilité ajoutée."
    else
      redirect_to @experience, alert: @availability.errors.full_messages.to_sentence
    end
  end

  def destroy
    @availability = @experience.experience_availabilities.find(params[:id])
    @availability.destroy
    redirect_to @experience, notice: "Disponibilité supprimée."
  end

  private

  def set_experience
    @experience = Experience.find(params[:experience_id])
  end

  def availability_params
    params.require(:experience_availability).permit(:available_on, :starts_at, :duration_minutes, :max_participants, :notes)
  end
end
