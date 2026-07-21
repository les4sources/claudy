# Gestion des paiements d'un séjour DEPUIS sa modale (calendrier / fiche client).
# La secrétaire vérifie les encaissements sur le compte bancaire ; elle doit
# pouvoir, sans quitter la modale :
#   * AJOUTER un paiement (montant, moyen, statut) au séjour (`create`) ;
#   * BASCULER le statut d'un paiement existant, typiquement pending → paid,
#     directement dans la liste (`update`).
#
# Après CHAQUE mutation, on recalcule le statut de paiement du séjour
# (`Stay#set_payment_status`, adossé à l'EXIGIBLE) : dès que l'encaissé couvre le
# solde, le séjour bascule en « paid ». La réponse redirige vers `stay_path`, ce
# qui recharge le turbo-frame `stay_<id>_payments` de la modale en place (même
# pattern que le CRUD des activités) — badge de statut et liste rafraîchis sans
# recharger toute la page.
#
# Sécurité : le paiement est TOUJOURS chargé via `Payment.where(stay_id: @stay.id)`
# — seuls les paiements DIRECTEMENT rattachés au séjour sont éditables ici. Les
# paiements du canal booking historique (sans `stay_id`) restent gérés par leur
# propre écran ; on ne les mute jamais depuis la modale séjour.
class StayPaymentsController < BaseController
  before_action :set_stay

  def create
    @payment = Payment.new(create_params.merge(stay: @stay))

    if @payment.save
      @stay.set_payment_status
      redirect_to stay_path(@stay), notice: "Paiement ajouté au séjour."
    else
      redirect_to stay_path(@stay),
                  alert: @payment.errors.full_messages.to_sentence.presence || "Ajout du paiement impossible."
    end
  end

  def update
    @payment = @stay.direct_payments.find(params[:id])

    if @payment.update(update_params)
      @stay.set_payment_status
      redirect_to stay_path(@stay), notice: "Paiement mis à jour."
    else
      redirect_to stay_path(@stay),
                  alert: @payment.errors.full_messages.to_sentence.presence || "Mise à jour du paiement impossible."
    end
  end

  private

  def set_stay
    @stay = Stay.find(params[:stay_id])
  end

  def create_params
    params.require(:payment).permit(:amount, :payment_method, :status)
  end

  def update_params
    params.require(:payment).permit(:amount, :payment_method, :status)
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "accounting",
      active_secondary: "payments"
    )
    @accounting_view = true
  end
end
