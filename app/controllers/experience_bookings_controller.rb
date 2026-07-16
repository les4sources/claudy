# Canal ADMIN de validation des activités (epic #55, Phase 2).
#
# Scoping d'autorisation : un porteur ne voit et n'agit que sur les
# `ExperienceBooking` de ses propres `Experience` ; un admin global voit tout.
# Toute la règle est centralisée dans `ExperienceBooking.for_user` — on charge
# TOUJOURS via cette portée, si bien qu'un porteur qui cible l'ID d'une
# réservation d'un autre porteur obtient un 404 (jamais une action réussie).
class ExperienceBookingsController < BaseController
  before_action :load_scoped_booking, only: [:update, :confirm, :new_refusal, :refuse]

  def index
    @experience_bookings = ExperienceBooking.for_user(current_user)
                                            .includes(experience_availability: :experience, stay: :customer)
                                            .order(created_at: :desc)
                                            .limit(100)
  end

  # Toggle historique (Phase 1) conservé, mais scoppé. Le modèle interdit de
  # passer en `refused` sans raison — ce chemin ne sert donc qu'à confirmer /
  # annuler, jamais à refuser à la légère.
  def update
    if @booking.update(status: params[:status])
      head :ok
    else
      head :unprocessable_entity
    end
  end

  # Validation (pending → confirmed) + notification au client.
  def confirm
    @booking.confirm!
    ActivitySelectionMailer.booking_confirmed(@booking).deliver_later
    redirect_to experience_bookings_path,
                notice: "Activité « #{@booking.experience.name} » confirmée. Le client est prévenu."
  end

  # Formulaire de refus (raison obligatoire).
  def new_refusal
  end

  # Application du refus (pending → refused) + notification au client avec la
  # raison et une invitation à re-choisir un créneau.
  def refuse
    @booking.refuse!(params.dig(:experience_booking, :refusal_reason).to_s)
    ActivitySelectionMailer.booking_refused(@booking).deliver_later
    redirect_to experience_bookings_path,
                notice: "Activité « #{@booking.experience.name} » refusée. Le client est prévenu."
  rescue ActiveRecord::RecordInvalid
    flash.now[:alert] = "Merci d'indiquer une raison pour le refus."
    render :new_refusal, status: :unprocessable_entity
  end

  private

  def load_scoped_booking
    @booking = ExperienceBooking.for_user(current_user).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # Réservation inexistante OU hors du périmètre du porteur : même réponse,
    # on ne divulgue pas l'existence de la réservation d'un autre porteur.
    respond_to do |format|
      format.html { redirect_to experience_bookings_path, alert: "Réservation introuvable." }
      format.any  { head :not_found }
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
