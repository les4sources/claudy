require "rails_helper"

# Commission de l'apporteur (Michael, 2026-10-18) : 10 % de l'HÉBERGEMENT pour
# Semisto, due seulement quand le séjour est confirmé ET entièrement payé.
RSpec.describe Stays::ReferralCommission do
  let(:customer) { Customer.create!(email: "commission@example.com", first_name: "Léa", last_name: "Apport") }

  # Hébergement 400 € ; le reste du total (repas, espaces…) n'entre pas dans
  # l'assiette : le séjour coûte 650 € en tout.
  def build_stay(status: "confirmed", referral: "semisto", lodging_cents: 40_000, total_cents: 65_000, dogs: 0)
    stay = Stay.create!(customer: customer, source: "reservation", status: status, referral: referral,
                        arrival_date: Date.today + 30, departure_date: Date.today + 32, dogs_count: dogs)
    booking = Booking.create!(firstname: "Léa", from_date: stay.arrival_date, to_date: stay.departure_date,
                              adults: 2, status: status, price_cents: lodging_cents)
    stay.stay_items.create!(bookable: booking)
    stay.update_columns(total_amount_cents: total_cents)
    stay.reload
  end

  def pay(stay, cents)
    Payment.create!(stay: stay, amount_cents: cents, status: "paid", payment_method: "transfer")
  end

  it "lit le taux dans Stay::REFERRALS" do
    commission = described_class.new(build_stay)
    expect(commission.rate).to eq(BigDecimal("0.10"))
    expect(commission.rate_label).to eq("10 %")
    expect(commission.label).to eq("Semisto")
  end

  it "porte sur l'hébergement seul, pas sur le total du séjour" do
    commission = described_class.new(build_stay)
    expect(commission.lodging_cents).to eq(40_000)
    expect(commission.amount_cents).to eq(4_000)
  end

  it "retire le supplément chien de l'assiette" do
    commission = described_class.new(build_stay(lodging_cents: 45_000, dogs: 1))
    expect(commission.lodging_cents).to eq(45_000 - Pricing::Catalog.dog_supplement_cents)
    expect(commission.amount_cents).to eq(((45_000 - Pricing::Catalog.dog_supplement_cents) * 0.10).round)
  end

  it "est due pour un séjour confirmé et entièrement payé" do
    stay = build_stay
    pay(stay, 65_000)
    commission = described_class.new(stay)
    expect(commission).to be_due
    expect(commission.pending_reasons).to be_empty
  end

  it "n'est pas due tant que le séjour n'est pas entièrement payé" do
    stay = build_stay
    pay(stay, 40_000)
    commission = described_class.new(stay)
    expect(commission).not_to be_due
    expect(commission.pending_reasons).to eq(["séjour pas entièrement payé"])
  end

  it "n'est pas due pour un séjour payé mais pas confirmé" do
    stay = build_stay(status: "pre_confirmed")
    pay(stay, 65_000)
    commission = described_class.new(stay)
    expect(commission).not_to be_due
    expect(commission.pending_reasons).to eq(["séjour pas encore confirmé"])
  end

  it "accepte un encaissé calculé en lot par l'appelant" do
    stay = build_stay
    expect(described_class.new(stay, paid_cents: 65_000)).to be_due
    expect(described_class.new(stay, paid_cents: 0)).not_to be_due
  end

  it "ne s'applique pas à un séjour sans apporteur" do
    commission = described_class.new(build_stay(referral: nil))
    expect(commission).not_to be_applicable
    expect(commission.amount_cents).to eq(0)
    expect(commission).not_to be_due
    expect(commission.pending_reasons).to be_empty
  end
end
