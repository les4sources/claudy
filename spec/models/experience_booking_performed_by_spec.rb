require "rails_helper"

# Une activité a un porteur principal, mais d'autres personnes peuvent tenir la
# prestation (Michael, 2026-10-13). Le relevé paie celle qui l'a tenue, au
# montant posé sur la réservation quand il diffère du calcul.
RSpec.describe ExperienceBooking, "prestation tenue par quelqu'un d'autre" do
  let(:bene)   { Human.create!(name: "Béné", email: "bene@example.com") }
  let(:magali) { Human.create!(name: "Magali", email: "magali@example.com") }
  let(:anes) do
    Experience.create!(name: "Bain d'ânes", human: bene, duration_hours: 2, fixed_price_cents: 12_000, price_cents: 0)
  end
  let(:customer) { Customer.create!(email: "client@example.com", customer_type: "individual") }
  let(:stay) { Stay.create!(customer: customer, arrival_date: Date.current - 10, departure_date: Date.current - 9) }
  let(:creneau) { ExperienceAvailability.create!(experience: anes, available_on: Date.current - 10, starts_at: "10:00") }

  def tenue!(**attrs)
    booking = described_class.create!(experience_availability: creneau, stay: stay, participants: 6, **attrs)
    booking.confirm!
    booking.mark_held!
    booking
  end

  it "est tenue par le porteur de l'activité quand personne n'est nommé" do
    booking = tenue!

    expect(booking.carrier).to eq(bene)
    expect(described_class.for_carrier(bene)).to include(booking)
  end

  it "paie la personne nommée, pas le porteur de l'activité" do
    booking = tenue!(performed_by: magali)

    expect(booking.carrier).to eq(magali)
    expect(described_class.for_carrier(magali)).to include(booking)
    expect(described_class.for_carrier(bene)).not_to include(booking)
    expect(CarrierStatements::Selection.new(human: magali).bookings).to eq([booking])
    expect(described_class.carriers).to include(bene, magali)
  end

  it "reste visible du porteur de l'activité, qui la valide" do
    booking = tenue!(performed_by: magali)

    expect(described_class.visible_to_carrier(bene)).to include(booking)
    expect(described_class.visible_to_carrier(magali)).to include(booking)
  end

  it "garde le montant posé à la main, et calcule sinon" do
    expect(tenue!(carrier_fee: "60").carrier_fee_cents).to eq(6_000)
    expect(tenue!.carrier_fee_cents).to eq(8_000)
  end

  it "se saisit en euros, virgule comprise" do
    booking = described_class.new(carrier_fee: "62,50")

    expect(booking.carrier_fee_cents).to eq(6_250)
    expect(booking.carrier_fee).to eq(62.5)
  end

  it "fige la personne et le montant une fois la prestation sur un relevé" do
    booking = tenue!(performed_by: magali)
    CarrierStatements::Generate.new(human: magali, period_from: Date.current - 30, period_to: Date.current).run!

    expect(booking.reload.update(performed_by: bene)).to be(false)
    expect(booking.reload.update(carrier_fee_cents: 1)).to be(false)
  end
end
