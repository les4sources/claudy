require "rails_helper"

# Paiement initial en attente à la création admin (refonte séjour 2026-07-22) :
# quand l'admin coche « Créer un paiement initial en attente », le Builder crée
# UN Payment `pending` sur le séjour. Montant = celui saisi (prérempli à
# l'acompte du devis) ; à défaut, l'acompte du devis. Non coché → aucun paiement
# (comportement admin historique). Aucun appel Stripe.
RSpec.describe "Reservations::Builder — paiement initial admin", type: :model do
  let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def build_draft
    Reservations::Draft.new(
      lodging_id: lodging.id, arrival_date: arrival, departure_date: departure,
      adults: 2, first_name: "Alice", last_name: "Martin",
      email: "init-pay@example.com", phone: "0470111222"
    )
  end

  def run_builder(**opts)
    Reservations::Builder.new(draft: build_draft, admin: true, status: "pending", source: "manual", **opts).tap(&:run!)
  end

  it "non coché → aucun paiement créé" do
    builder = run_builder(create_initial_payment: false)
    expect(builder.stay.payments).to be_empty
    expect(builder.payment).to be_nil
  end

  it "coché avec un montant → un Payment pending au montant saisi" do
    builder = run_builder(create_initial_payment: true, initial_payment_amount_cents: 12_500)
    payments = builder.stay.payments
    expect(payments.size).to eq(1)
    payment = payments.first
    expect(payment.status).to eq("pending")
    expect(payment.amount_cents).to eq(12_500)
    expect(payment.stay_id).to eq(builder.stay.id)
  end

  it "coché sans montant → retombe sur l'acompte du devis" do
    deposit = build_draft.quote.deposit_cents
    expect(deposit).to be > 0 # sanity : le séjour a bien un acompte à préremplir
    builder = run_builder(create_initial_payment: true, initial_payment_amount_cents: nil)
    expect(builder.stay.payments.first.amount_cents).to eq(deposit)
  end

  it "coché avec un montant nul/négatif → aucun paiement (jamais un Payment invalide)" do
    builder = run_builder(create_initial_payment: true, initial_payment_amount_cents: 0)
    expect(builder.stay.payments).to be_empty
    expect(builder.payment).to be_nil
  end
end
