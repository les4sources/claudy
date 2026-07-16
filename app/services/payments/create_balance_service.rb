module Payments
  # Création (ou réutilisation) du paiement de SOLDE d'un séjour, puis ouverture
  # d'une session Stripe Checkout du montant EXIGIBLE (epic #55, Phase 3).
  #
  # Montant réglé = `stay.balance_due_cents` = (hébergement/espaces + activités
  # CONFIRMED) − encaissé. Les activités `pending` (non validées par le porteur)
  # n'y entrent JAMAIS. Payable à tout moment tant que l'exigible est positif :
  # l'assiette est recalculée à chaque initiation, ce qui tolère naturellement
  # les paiements partiels/successifs.
  #
  # On réutilise un éventuel paiement `pending` déjà rattaché au séjour (garde-fou
  # anti-doublon contre une double soumission) en réalignant son montant sur
  # l'exigible courant ; sinon on en crée un, ANCRÉ sur le Stay (`stay_id`). Le
  # Checkout et le webhook réutilisent tels quels le mécanisme de l'acompte
  # (epic #26) : `PayService` pour la session, `Webhooks::StripeService` +
  # `StripeEvent` pour l'idempotence côté retour.
  class CreateBalanceService < ServiceBase
    attr_reader :stay, :payment, :checkout_session_url

    def initialize(stay:)
      @stay = stay
      @report_errors = true
    end

    def run
      catch_error { run! }
    end

    def run!
      amount_cents = stay.balance_due_cents
      unless amount_cents.positive?
        set_error_message("Ce séjour est déjà soldé : aucun montant n'est exigible.")
        return false
      end

      @payment = upsert_pending_payment!(amount_cents)

      pay = Payments::PayService.new(payment_id: @payment.id)
      raise pay.error_message(default: "Le paiement en ligne n'a pas pu être initialisé.") unless pay.run

      @checkout_session_url = pay.checkout_session_url
      true
    end

    private

    # Un seul paiement `pending` vivant à la fois pour ce séjour : on réutilise
    # celui déjà présent (double-clic) en réalignant son montant, sinon on crée
    # un paiement neuf rattaché au Stay.
    def upsert_pending_payment!(amount_cents)
      existing = stay.payments.pending.order(:created_at).last
      if existing
        existing.update!(amount_cents: amount_cents)
        existing
      else
        Payment.create!(
          stay: stay,
          amount_cents: amount_cents,
          status: "pending",
          payment_method: "card"
        )
      end
    end
  end
end
