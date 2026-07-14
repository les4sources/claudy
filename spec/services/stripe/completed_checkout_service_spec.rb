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

  it "ne plante pas sur un paiement historique sans séjour" do
    payment = Payment.create!(booking: booking, amount_cents: 48_500,
                              status: "pending", payment_method: "card")

    expect { described_class.new(payment: payment).run!(webhook_params) }.not_to raise_error

    expect(booking.reload.payment_status).to eq("paid")
  end
end
