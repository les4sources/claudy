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
      email_customer_deposit_received
      email_customer_coworking_purchase
      true
    end

    private

    # Coworking (epic #126, Phase 3) : un paiement ancré sur un pack marque
    # celui-ci comme payé (statut dérivé). On confirme l'achat au client. Pas de
    # séjour ni de booking ici — les emails ci-dessus sont donc no-op.
    def email_customer_coworking_purchase
      pack = payment.coworking_pack
      return if pack.nil?

      CoworkingMailer.pack_purchased(pack).deliver_later
    end

    def email_admin
      AdminMailer.payment_received(payment).deliver_later
    end

    # Second email client du flux funnel (décision 2026-07-20) : « acompte bien
    # reçu, notre équipe valide votre demande ». UNIQUEMENT au premier
    # encaissement d'un séjour encore `pending` — le paiement du solde ou tout
    # encaissement d'un séjour déjà confirmé ne redéclenche pas ce message de
    # pré-validation. L'idempotence webhook est déjà garantie en amont
    # (StripeEvent) ; le garde « premier paid » protège en plus contre un rejeu.
    def email_customer_deposit_received
      stay = payment.stay
      return unless stay&.status == "pending"
      return if stay.customer&.email.blank?
      return if stay.payments.paid.where.not(id: payment.id).exists?

      ReservationMailer.deposit_received(payment).deliver_later
    end
  end
end
