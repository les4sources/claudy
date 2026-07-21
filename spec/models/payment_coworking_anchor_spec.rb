require "rails_helper"

# Epic #126, Phase 1 — l'invariant du verrouillage (epic #26, Phase 4) devient
# « stay_id OU coworking_pack_id ».
RSpec.describe "Payment — ancrage séjour ou pack de coworking", type: :model do
  let(:customer) { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com") }
  let(:stay) { Stay.create!(customer: customer, arrival_date: Date.new(2026, 9, 7), departure_date: Date.new(2026, 9, 9)) }
  let(:pack) { CoworkingPack.create!(customer: customer, days_total: 5, payment_method: "bank_transfer") }

  it "accepte un paiement ancré sur un séjour (sans pack)" do
    payment = Payment.new(stay: stay, amount_cents: 5_000, payment_method: "card", status: "paid")
    expect(payment).to be_valid
  end

  it "accepte un paiement ancré sur un pack de coworking (sans séjour)" do
    payment = Payment.new(coworking_pack: pack, amount_cents: 8_000, payment_method: "bank_transfer", status: "pending")
    expect(payment).to be_valid
  end

  it "refuse un paiement sans aucune ancre" do
    payment = Payment.new(amount_cents: 5_000, payment_method: "card", status: "paid")
    expect(payment).not_to be_valid
    expect(payment.errors[:stay]).to be_present
  end

  it "refuse un paiement portant les deux ancres" do
    payment = Payment.new(stay: stay, coworking_pack: pack, amount_cents: 5_000,
                          payment_method: "card", status: "paid")
    expect(payment).not_to be_valid
  end
end
