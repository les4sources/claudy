module Stripe
  class CompletedCheckoutService < ServiceBase
    attr_reader :payment

    def initialize(payment:)
      @payment = payment
    end

    def run!(params = {})
      # Le webhook enregistre un fait externe (Stripe a encaissé) : le statut DOIT
      # être persisté même sur un Payment legacy sans stay_id (invalide au sens du
      # verrouillage Phase 4). `update` non-bang échouait en silence → booking
      # jamais marqué payé malgré l'encaissement ; `update!` ferait planter le
      # webhook (Stripe rejouerait en boucle, admin non notifié). On persiste en
      # contournant la validation, qui ne concerne pas la véracité du paiement.
      payment.assign_attributes(
        status: "paid",
        stripe_checkout_session_id: params[:stripe_checkout_session_id],
        stripe_payment_intent_id: params[:stripe_payment_intent_id]
      )
      payment.save!(validate: false)
      # Stay-first (epic #26, Phase 2) : le statut du séjour fait foi. Le booking
      # garde le sien tant que la colonne existe — et il peut désormais être
      # absent (séjour sans hébergement).
      @payment.stay&.set_payment_status
      @payment.booking&.set_payment_status
      email_admin
      true
    end

    private

    def email_admin
      AdminMailer.payment_received(payment).deliver_later
    end
  end
end
