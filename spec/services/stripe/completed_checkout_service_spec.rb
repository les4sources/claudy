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

  # Décision 2026-07-20 : l'acompte confirme la réservation → le client reçoit
  # « acompte bien reçu » au PREMIER encaissement d'un séjour pending, et
  # uniquement là.
  describe "email client « acompte reçu »" do
    before { ActiveJob::Base.queue_adapter = :test }

    it "part au premier encaissement d'un séjour pending" do
      payment = Payment.create!(stay: stay, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      expect {
        described_class.new(payment: payment).run!(webhook_params)
      }.to have_enqueued_mail(ReservationMailer, :deposit_received)
    end

    it "ne repart PAS pour un paiement suivant (solde) du même séjour" do
      Payment.create!(stay: stay, amount_cents: 24_250, status: "paid", payment_method: "card")
      balance = Payment.create!(stay: stay, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      expect {
        described_class.new(payment: balance).run!(webhook_params)
      }.not_to have_enqueued_mail(ReservationMailer, :deposit_received)
    end

    it "ne part pas pour un séjour déjà confirmé" do
      stay.update!(status: "confirmed")
      payment = Payment.create!(stay: stay, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      expect {
        described_class.new(payment: payment).run!(webhook_params)
      }.not_to have_enqueued_mail(ReservationMailer, :deposit_received)
    end

    it "ne part pas pour un paiement legacy sans séjour" do
      payment = Payment.new(booking: booking, amount_cents: 48_500,
                            status: "pending", payment_method: "card")
      payment.save!(validate: false)

      expect {
        described_class.new(payment: payment).run!(webhook_params)
      }.not_to have_enqueued_mail(ReservationMailer, :deposit_received)
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
