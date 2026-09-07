require "rails_helper"

# Epic #26, Phase 2 — le webhook `checkout.session.completed` met à jour le
# statut de paiement du SÉJOUR (et celui du booking tant qu'il existe).
RSpec.describe Stripe::CompletedCheckoutService do
  let(:customer) { Customer.create!(email: "hook@example.com", customer_type: "individual") }
  let(:booking) do
    Booking.create!(firstname: "Léa", from_date: Date.today + 10, to_date: Date.today + 12,
                    adults: 2, status: "pending", price_cents: 48_500, payment_status: "pending")
  end
  let(:stay) do
    Stay.create!(customer: customer, source: "reservation", status: "pending",
                 total_amount_cents: 48_500)
  end

  let(:webhook_params) do
    { stripe_checkout_session_id: "cs_test_123", stripe_payment_intent_id: "pi_test_123" }
  end

  it "passe le paiement en payé et recalcule le statut du séjour" do
    payment = Payment.create!(stay: stay, booking: booking, amount_cents: 48_500,
                              status: "pending", payment_method: "card")

    described_class.new(payment: payment).run!(webhook_params)

    expect(payment.reload.status).to eq("paid")
    expect(payment.stripe_checkout_session_id).to eq("cs_test_123")
    expect(stay.reload.payment_status).to eq("paid")
  end

  it "met aussi à jour le statut du booking tant qu'il existe" do
    payment = Payment.create!(stay: stay, booking: booking, amount_cents: 48_500,
                              status: "pending", payment_method: "card")

    described_class.new(payment: payment).run!(webhook_params)

    expect(booking.reload.payment_status).to eq("paid")
  end

  it "marque le séjour partiellement payé quand l'acompte ne couvre pas le total" do
    payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                              status: "pending", payment_method: "card")

    described_class.new(payment: payment).run!(webhook_params)

    expect(stay.reload.payment_status).to eq("partially_paid")
  end

  it "ne plante pas sur un séjour SANS hébergement (aucun booking)" do
    payment = Payment.create!(stay: stay, amount_cents: 48_500,
                              status: "pending", payment_method: "card")

    expect { described_class.new(payment: payment).run!(webhook_params) }.not_to raise_error

    expect(payment.reload.status).to eq("paid")
    expect(stay.reload.payment_status).to eq("paid")
  end

  # Issue #215 — l'acompte CONFIRME la réservation. Plus d'email intermédiaire
  # « acompte bien reçu » : l'encaissement bascule le séjour en `confirmed`, via
  # `Stays::QuickStatusUpdater` (qui propage aux réservables) et envoie l'unique
  # email client `ReservationMailer#stay_confirmed`.
  describe "confirmation automatique au premier encaissement (issue #215)" do
    around do |example|
      ActionMailer::Base.deliveries.clear
      example.run
      ActionMailer::Base.deliveries.clear
    end

    def confirmation_emails
      ActionMailer::Base.deliveries.select { |m| m.subject.to_s.match?(/est confirmé/i) }
    end

    it "bascule un séjour pré-confirmé en confirmé" do
      stay.update!(status: "pre_confirmed")
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      described_class.new(payment: payment).run!(webhook_params)

      expect(stay.reload.status).to eq("confirmed")
    end

    # LE piège de l'issue : le veto de dispo suit le statut des RÉSERVABLES.
    # Un séjour confirmé dont le Booking reste `pending` ne bloque rien.
    it "propage le statut confirmé aux réservables du séjour" do
      stay.update!(status: "pre_confirmed")
      stay.stay_items.create!(bookable: booking)
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      described_class.new(payment: payment).run!(webhook_params)

      expect(booking.reload.status).to eq("confirmed")
    end

    it "envoie EXACTEMENT un email client « séjour confirmé »" do
      stay.update!(status: "pre_confirmed")
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      described_class.new(payment: payment).run!(webhook_params)

      expect(confirmation_emails.size).to eq(1)
      expect(confirmation_emails.first.to).to eq(["hook@example.com"])
    end

    it "bascule aussi un séjour resté pending (acompte demandé hors funnel)" do
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      described_class.new(payment: payment).run!(webhook_params)

      expect(stay.reload.status).to eq("confirmed")
    end

    it "ne rebascule ni ne renotifie sur un paiement de SOLDE (séjour déjà confirmé)" do
      stay.update!(status: "confirmed")
      Payment.create!(stay: stay, amount_cents: 24_250, status: "paid", payment_method: "card")
      balance = Payment.create!(stay: stay, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      described_class.new(payment: balance).run!(webhook_params)

      expect(stay.reload.status).to eq("confirmed")
      expect(confirmation_emails).to be_empty
    end

    it "ne confirme rien pour un paiement legacy sans séjour" do
      payment = Payment.new(booking: booking, amount_cents: 48_500,
                            status: "pending", payment_method: "card")
      payment.save!(validate: false)

      expect { described_class.new(payment: payment).run!(webhook_params) }.not_to raise_error
      expect(confirmation_emails).to be_empty
    end

    # Coworking (epic #126) : aucun séjour, donc aucun effet de bord.
    it "n'a aucun effet sur un paiement de pack coworking" do
      pack = CoworkingPack.create!(customer: customer, days_total: 5, payment_method: "card",
                                   expires_at: Date.current + 1.year)
      payment = Payment.new(coworking_pack: pack, amount_cents: 15_000,
                            status: "pending", payment_method: "card")
      payment.save!(validate: false)

      expect { described_class.new(payment: payment).run!(webhook_params) }.not_to raise_error
      expect(confirmation_emails).to be_empty
    end
  end

  it "ne plante pas sur un paiement historique sans séjour" do
    # Donnée LEGACY d'avant le verrouillage Phase 4 (aucun stay_id) : on
    # contourne la validation pour reproduire l'état réel en base. Le webhook
    # doit rester robuste sur ces enregistrements historiques.
    payment = Payment.new(booking: booking, amount_cents: 48_500,
                          status: "pending", payment_method: "card")
    payment.save!(validate: false)

    expect { described_class.new(payment: payment).run!(webhook_params) }.not_to raise_error

    expect(booking.reload.payment_status).to eq("paid")
  end
end
