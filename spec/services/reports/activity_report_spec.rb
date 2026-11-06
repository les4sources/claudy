require "rails_helper"

RSpec.describe Reports::ActivityReport do
  let(:customer) { Customer.create!(email: "activites-report@example.com", customer_type: "individual") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "confirmed") }
  let(:carrier) { Human.create!(name: "Béné") }
  let(:donkeys) { Experience.create!(name: "Ânes test", price_cents: 0, fixed_price_cents: 12_000, human: carrier) }
  let(:pizza) { Experience.create!(name: "Pizza test", price_cents: 500, fixed_price_cents: 21_000) }

  def booking(experience, on:, participants: 10, status: "confirmed", on_stay: stay, fee: nil, outcome: nil)
    availability = ExperienceAvailability.create!(experience: experience, available_on: on, starts_at: "10:00")
    record = ExperienceBooking.create!(experience_availability: availability, stay: on_stay,
                                       participants: participants, status: status)
    record.update_columns(carrier_fee_cents: fee, outcome: outcome)
    record
  end

  subject(:report) { described_class.new(year: 2026, today: Date.new(2026, 11, 6)) }

  it "compte les réservations confirmées de l'année, au barème de l'activité" do
    booking(donkeys, on: Date.new(2026, 5, 16), participants: 12, fee: 6_000, outcome: "held")
    booking(pizza, on: Date.new(2026, 5, 20), participants: 8, fee: 9_000, outcome: "held")
    booking(pizza, on: Date.new(2026, 8, 27), participants: 17, fee: 9_000)

    expect(report.totals.bookings).to eq(3)
    expect(report.totals.participants).to eq(37)
    # 120 € + (210 € + 8 × 5 €) + (210 € + 17 × 5 €)
    expect(report.totals.revenue_cents).to eq(12_000 + 25_000 + 29_500)
    expect(report.totals.carrier_fee_cents).to eq(24_000)
    expect(report.totals.margin_cents).to eq(66_500 - 24_000)
    expect(report.by_month[5].bookings).to eq(2)
    expect(report.by_month[8].revenue_cents).to eq(29_500)
    expect(report.by_month[1].bookings).to eq(0)
  end

  it "classe les activités par chiffre d'affaires et donne leur part" do
    booking(donkeys, on: Date.new(2026, 5, 16))
    booking(pizza, on: Date.new(2026, 6, 1), participants: 8)

    rows = report.by_experience
    expect(rows.map(&:name)).to eq(["Pizza test", "Ânes test"])
    expect(report.share_of(rows.first)).to eq(67.6)
  end

  it "laisse hors du total les réservations à valider, refusées, annulées, hors année ou sur un séjour annulé" do
    canceled_stay = Stay.create!(customer: customer, source: "manual", status: "canceled")
    booking(donkeys, on: Date.new(2026, 3, 1), status: "pending", participants: 5)
    booking(donkeys, on: Date.new(2026, 3, 2), status: "cancelled")
    booking(donkeys, on: Date.new(2025, 12, 31))
    booking(donkeys, on: Date.new(2026, 3, 3), on_stay: canceled_stay)

    expect(report.totals.bookings).to eq(0)
    expect(report.pending_totals.bookings).to eq(1)
    expect(report.pending_totals.participants).to eq(5)
  end

  it "dit la tenue et les rémunérations manquantes" do
    booking(donkeys, on: Date.new(2026, 5, 16), outcome: "held", fee: 6_000)
    booking(donkeys, on: Date.new(2026, 6, 16), outcome: "no_show", fee: 6_000)
    booking(donkeys, on: Date.new(2026, 10, 16))
    booking(donkeys, on: Date.new(2026, 12, 16))

    expect(report.outcomes).to eq(held: 1, no_show: 1, to_declare: 1, upcoming: 1)
    expect(report.totals.missing_fee).to eq(2)
  end

  it "garde une activité supprimée depuis, à son prix" do
    booking(donkeys, on: Date.new(2026, 5, 16))
    donkeys.soft_delete!(validate: false)

    row = described_class.new(year: 2026).by_experience.first
    expect(row.deleted?).to be(true)
    expect(row.totals.revenue_cents).to eq(12_000)
  end
end
