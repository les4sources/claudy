# Canal ADMIN de validation des activités (epic #55, Phase 2) et CRUD admin
# d'une activité sur un séjour (epic #55, Phase 6).
#
# Scoping d'autorisation : un porteur ne voit et n'agit que sur les
# `ExperienceBooking` de ses propres `Experience` ; un admin global voit tout.
# Toute la règle est centralisée dans `ExperienceBooking.for_user` (édition /
# suppression / validation) et `ExperienceAvailability.for_user` (création) — on
# charge TOUJOURS via ces portées, si bien qu'un porteur qui cible l'ID d'une
# réservation ou d'un créneau d'un autre porteur obtient un 404 / un refus
# (jamais une action réussie hors périmètre).
class ExperienceBookingsController < BaseController
  before_action :load_scoped_booking, only: [:update, :destroy, :confirm, :new_refusal, :refuse]

  def index
    @experience_bookings = ExperienceBooking.for_user(current_user)
                                            .includes(experience_availability: :experience, stay: :customer)
                                            .order(created_at: :desc)
                                            .limit(100)
  end

  # Ajout admin d'une activité SUR un séjour donné (epic #55, Phase 6).
  # L'admin choisit un créneau (`ExperienceAvailability`), un nombre de
  # participants et le STATUT INITIAL :
  #   * `pending`   → à valider par le porteur : entre dans le flux de validation
  #     normal (Phase 2) — la réservation apparaît dans l'index du porteur et
  #     n'est PAS encore exigible (Phase 3) ;
  #   * `confirmed` → déjà validé par l'admin : court-circuite la validation
  #     porteur (la réservation n'est jamais « à valider ») et devient
  #     immédiatement exigible au solde (Phase 3).
  # Le créneau est chargé via `ExperienceAvailability.for_user` : un porteur ne
  # peut ajouter que sur SES propres activités.
  def create
    @stay = Stay.find(params[:stay_id])
    availability = ExperienceAvailability.for_user(current_user)
                                         .find_by(id: create_params[:experience_availability_id])

    # Créneau hors périmètre du porteur OU inexistant : même réponse, on ne
    # divulgue pas l'existence du créneau d'un autre porteur.
    return deny_out_of_scope unless availability

    booking = @stay.experience_bookings.new(
      experience_availability: availability,
      participants: create_params[:participants],
      status: chosen_status
    )

    if booking.save
      refresh_stay_totals!(@stay)
      redirect_to stay_path(@stay),
                  notice: "Activité « #{availability.experience.name} » ajoutée au séjour."
    else
      redirect_to stay_path(@stay),
                  alert: booking.errors.full_messages.to_sentence.presence || "Ajout impossible."
    end
  end

  # Édition du nombre de participants d'une activité (Phase 6) — et toggle
  # historique de statut (Phase 1), conservé. Le modèle interdit de passer en
  # `refused` sans raison. Toute modification recalcule le total du séjour.
  def update
    if @booking.update(booking_update_params)
      refresh_stay_totals!(@booking.stay)
      respond_to do |format|
        format.html { redirect_to stay_path(@booking.stay), notice: "Activité mise à jour." }
        format.any  { head :ok }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to stay_path(@booking.stay),
                      alert: @booking.errors.full_messages.to_sentence.presence || "Modification impossible."
        end
        format.any { head :unprocessable_entity }
      end
    end
  end

  # Retrait d'une activité d'un séjour (Phase 6). `ExperienceBooking` n'a pas de
  # soft-deletion propre : on bascule en `cancelled` (exclu du scope `active` et
  # donc du total — cf. `Stay#recompute_aggregates!`). PaperTrail garde la trace.
  def destroy
    @booking.update!(status: "cancelled")
    refresh_stay_totals!(@booking.stay)
    respond_to do |format|
      format.html { redirect_to stay_path(@booking.stay), notice: "Activité retirée du séjour." }
      format.any  { head :ok }
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

  def create_params
    params.fetch(:experience_booking, {}).permit(:experience_availability_id, :participants, :status)
  end

  # Statut initial choisi par l'admin, borné aux deux seules valeurs légitimes à
  # la création (Phase 6, AC-2). Un `refused`/`cancelled` ne se POSE jamais à la
  # création : le refus passe par le flux Phase 2 (raison obligatoire), le retrait
  # par `destroy`. À défaut de choix explicite, on retombe sur `pending`.
  def chosen_status
    requested = create_params[:status].to_s
    ExperienceBooking::ADMIN_CREATABLE_STATUSES.include?(requested) ? requested : "pending"
  end

  # Édition : nombre de participants (formulaire admin Phase 6) et/ou toggle de
  # statut historique (Phase 1, statut au premier niveau des params).
  def booking_update_params
    attrs = {}
    attrs[:status] = params[:status] if params.key?(:status)
    if params[:experience_booking].present?
      attrs.merge!(params.require(:experience_booking).permit(:participants).to_h.symbolize_keys)
    end
    attrs
  end

  # Toute mutation d'activité recalcule le TOTAL du séjour (activités actives
  # incluses — Phase 1) PUIS le statut de paiement, adossé à l'EXIGIBLE (Phase 3).
  # Un `confirmed` ajouté augmente l'exigible ; un `pending` non ; un retrait le
  # baisse — le statut de paiement suit en conséquence.
  def refresh_stay_totals!(stay)
    stay.recompute_aggregates!
    stay.set_payment_status
  end

  def deny_out_of_scope
    respond_to do |format|
      format.html { redirect_to stay_path(@stay), alert: "Créneau introuvable." }
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
