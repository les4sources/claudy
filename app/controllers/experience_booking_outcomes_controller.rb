# Canal JETON de déclaration de tenue (epic #244, phase 2).
#
# Même partage que la validation (epic #55, phase 2) :
#   * « A EU LIEU » est bénin mais mutant. On ne mute JAMAIS sur un GET — un
#     antivirus ou un proxy mail préchargent les liens, et une saison entière se
#     déclarerait tenue sans que personne n'ait cliqué. Le lien mène à une page
#     de confirmation dont le bouton POSTe.
#   * « N'A PAS EU LIEU » a des conséquences (le créneau sort de la
#     rémunération) : il exige une connexion et renvoie vers l'écran admin, où
#     l'on voit ce qu'on fait.
#
# Le jeton a sa propre portée (`OUTCOME_TOKEN_PURPOSE`) : un lien de validation
# ne peut pas servir à déclarer une tenue, ni l'inverse.
class ExperienceBookingOutcomesController < ActionController::Base
  layout "public"

  before_action :authenticate_user!, only: [:no_show]

  def show
    @booking = ExperienceBooking.find_by_outcome_token(params[:token])
    return render :invalid, status: :not_found if @booking.nil?
  end

  def held
    @booking = ExperienceBooking.find_by_outcome_token(params[:token])
    return render :invalid, status: :not_found if @booking.nil?

    # Idempotent : un second clic sur le lien du mail ne réécrit pas la date ni
    # l'auteur du verdict déjà posé.
    @booking.mark_held! unless @booking.outcome_recorded?
    render :recorded
  rescue ExperienceBooking::OutcomeNotRecordable => e
    @message = e.message
    render :refused, status: :unprocessable_entity
  end

  def no_show
    booking = ExperienceBooking.find_by_outcome_token(params[:token])
    return render :invalid, status: :not_found if booking.nil?

    unless ExperienceBooking.for_user(current_user).exists?(booking.id)
      return render :forbidden, status: :forbidden
    end

    redirect_to outcomes_experience_bookings_path,
                notice: "Marque « n'a pas eu lieu » sur #{booking.experience.name} ci-dessous."
  end
end
