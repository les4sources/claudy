require "rails_helper"

# Epic #55, Phase 3 — le webhook Stripe encaisse le SOLDE d'un séjour.
#
# Le paiement du solde réutilise TEL QUEL le mécanisme de l'acompte (epic #26) :
# `checkout.session.completed` → `Webhooks::StripeService` → marque le Payment
# `paid` et recalcule le statut du séjour. L'idempotence est garantie par
# `StripeEvent` (dédup sur `webhook_id`) : un même événement rejoué n'a aucun
# effet de bord (Stripe rejoue en cas de timeout/retry).
RSpec.describe Webhooks::StripeService do
  let(:customer) { Customer.create!(email: "hook-solde@example.com", customer_type: "individual") }

  let(:booking) do
    Booking.create!(firstname: "Sol", from_date: Date.today + 10, to_date: Date.today + 12,
                    adults: 2, status: "confirmed", price_cents: 40_000, payment_status: "pending")
  end

  let(:stay) do
    s = Stay.create!(customer: customer, source: "reservation", status: "pending",
                     total_amount_cents: 40_000)
    s.stay_items.create!(bookable: booking)
    s
  end

  # Paiement du SOLDE (ancré sur le Stay), en attente d'encaissement.
  let(:balance_payment) do
    Payment.create!(stay: stay, booking: booking, amount_cents: 40_000,
                    status: "pending", payment_method: "card")
  end

  # Fabrique un faux événement Stripe. `data.object` doit répondre à la fois à
  # `[:client_reference_id]` (accès hash) ET à `.id` / `.payment_intent`
  # (méthodes) — c'est ce que le service consomme.
  def fake_event(webhook_id:, client_reference_id:)
    object = double("object", id: "cs_test_#{webhook_id}", payment_intent: "pi_test_#{webhook_id}")
    allow(object).to receive(:[]).with(:client_reference_id).and_return(client_reference_id)
    data = double("data", object: object)
    double("event", id: webhook_id, type: "checkout.session.completed", data: data)
  end

  it "encaisse le solde : Payment payé + séjour marqué payé" do
    event = fake_event(webhook_id: "evt_solde_1", client_reference_id: balance_payment.id)

    described_class.new(event: event).run!

    expect(balance_payment.reload.status).to eq("paid")
    expect(balance_payment.stripe_payment_intent_id).to eq("pi_test_evt_solde_1")
    expect(stay.reload.payment_status).to eq("paid")
    expect(StripeEvent.where(webhook_id: "evt_solde_1").count).to eq(1)
  end

  it "est idempotent : un même événement rejoué n'a aucun effet de bord" do
    event = fake_event(webhook_id: "evt_solde_dup", client_reference_id: balance_payment.id)

    described_class.new(event: event).run!
    first_paid_at = balance_payment.reload.updated_at

    # Rejeu du MÊME webhook_id.
    expect {
      described_class.new(event: event).run!
    }.not_to change { StripeEvent.where(webhook_id: "evt_solde_dup").count }

    # Le paiement n'est pas re-traité (pas de nouvelle écriture).
    expect(balance_payment.reload.updated_at).to eq(first_paid_at)
    expect(StripeEvent.where(webhook_id: "evt_solde_dup").count).to eq(1)
  end

  it "marque partially_paid quand le solde encaissé ne couvre pas encore l'exigible" do
    partial = Payment.create!(stay: stay, booking: booking, amount_cents: 25_000,
                              status: "pending", payment_method: "card")
    event = fake_event(webhook_id: "evt_partiel", client_reference_id: partial.id)

    described_class.new(event: event).run!

    expect(stay.reload.payment_status).to eq("partially_paid")
  end
end
