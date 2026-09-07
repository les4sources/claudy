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
      confirm_stay_on_first_payment!
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

    # L'ACOMPTE CONFIRME LA RÉSERVATION (issue #215, décision Michael du
    # 2026-08-31). Le flux s'arrêtait ici sur un « acompte bien reçu, notre
    # équipe valide votre demande » qui exigeait ensuite une seconde action
    # humaine. Puisque le Pôle Accueil a DÉJÀ regardé la demande pour la
    # pré-confirmer, il n'y a plus rien à valider : l'encaissement confirme, et
    # le client reçoit UN seul email — « votre séjour est confirmé ».
    #
    # ⚠️ On passe par `Stays::QuickStatusUpdater` et jamais par un
    # `stay.update!(status: "confirmed")` à la main : le veto de disponibilité
    # suit le statut des RÉSERVABLES, pas celui du séjour. Un séjour confirmé
    # dont le Booking resterait `pending` ne bloquerait rien et laisserait passer
    # un surbooking silencieux. Le service propage le statut aux bookables et
    # délègue l'email à `Stays::ConfirmationNotifier`, qui garde ses garde-fous.
    #
    # Bornes : uniquement au PREMIER encaissement d'un séjour pas encore
    # confirmé. Un paiement de solde sur un séjour déjà `confirmed` ne rebascule
    # rien, et un paiement de pack coworking (sans séjour) n'entre pas ici.
    def confirm_stay_on_first_payment!
      stay = payment.stay
      return if stay.nil?
      return if stay.status == "confirmed"
      return if stay.payments.paid.where.not(id: payment.id).exists?

      Stays::QuickStatusUpdater.new(stay: stay, status: "confirmed").run
    end
  end
end
