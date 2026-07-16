# Canal JETON de validation des activités (epic #55, Phase 2).
#
# Le lien envoyé au porteur dans l'email `animateur_notification` porte un
# `signed_id` Rails à portée d'UN seul `ExperienceBooking` (purpose +
# expiration) — impossible à forger ou à rejouer ailleurs.
#
# Choix de sécurité :
#   * VALIDER  = action bénigne mais mutante. On ne mute JAMAIS sur un GET
#     (préchargeable par un antivirus / proxy mail). Le lien mène à une page de
#     confirmation légère (`show`) dont le bouton POSTe vers `confirm` (protégé
#     par CSRF). C'est le « 1 clic » côté porteur, sans mutation sur GET.
#   * REFUSER = exige une raison, donc un compte. Le lien (`refuse`) force la
#     connexion Devise puis renvoie vers le formulaire de refus du canal admin.
#     Jamais de refus anonyme en 1 clic.
class ExperienceBookingValidationsController < ActionController::Base
  layout "public"

  before_action :authenticate_user!, only: [:refuse]

  # Page de confirmation de validation (GET, anonyme). Ne mute rien.
  def show
    @booking = ExperienceBooking.find_by_validation_token(params[:token])
    return render :invalid, status: :not_found if @booking.nil?
  end

  # Applique la validation (POST, anonyme mais protégé CSRF via le formulaire
  # de la page `show`). Idempotent : ne re-confirme pas une réservation déjà
  # traitée.
  def confirm
    @booking = ExperienceBooking.find_by_validation_token(params[:token])
    return render :invalid, status: :not_found if @booking.nil?

    if @booking.pending?
      @booking.confirm!
      ActivitySelectionMailer.booking_confirmed(@booking).deliver_later
    end
    render :confirmed
  end

  # Amorce le refus depuis l'email : impose la connexion (Devise mémorise le
  # lien et y revient après login), vérifie que le porteur connecté est bien
  # propriétaire de l'activité, puis renvoie vers le formulaire de refus admin.
  def refuse
    booking = ExperienceBooking.find_by_validation_token(params[:token])
    return render :invalid, status: :not_found if booking.nil?

    unless ExperienceBooking.for_user(current_user).exists?(booking.id)
      return render :forbidden, status: :forbidden
    end

    redirect_to new_refusal_experience_booking_path(booking)
  end
end
