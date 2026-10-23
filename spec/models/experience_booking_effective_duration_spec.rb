require "rails_helper"

# Une activité a une durée standard, mais ce n'est pas toujours elle qu'on
# preste (Michael, 2026-10-23 : les ânes de Béné, 2 h de durée standard, 1 h 30 avec des
# tout-petits, séjour #1567). Le porteur est payé pour la durée prestée.
RSpec.describe ExperienceBooking, "durée effective" do
  let(:bene) { Human.create!(name: "Béné", email: "bene@example.com") }
  let(:anes) do
    Experience.create!(name: "Bain d'ânes", human: bene, duration_hours: 2, carrier_hourly_rate: "30",
                       fixed_price_cents: 12_000, price_cents: 0)
  end
  let(:customer) { Customer.create!(email: "client@example.com", customer_type: "individual") }
  let(:stay) { Stay.create!(customer: customer, arrival_date: Date.current - 10, departure_date: Date.current - 9) }
  let(:creneau) { ExperienceAvailability.create!(experience: anes, available_on: Date.current - 10, starts_at: "10:00") }

  def tenue!(**attrs)
    booking = described_class.create!(experience_availability: creneau, stay: stay, participants: 10, **attrs)
    booking.confirm!
    booking.mark_held!
    booking
  end

  it "vaut la durée standard de l'activité par défaut" do
    booking = tenue!

    expect(booking.duration_minutes).to be_nil
    expect(booking.effective_duration_minutes).to eq(120)
    expect(booking.effective_duration).to eq("2h")
    expect(booking).not_to be_duration_adjusted
    expect(booking.carrier_fee_cents).to eq(6_000)
  end

  it "paie la durée prestée, et le montant suit quand elle change après validation" do
    booking = tenue!
    booking.update!(effective_duration: "1h30")

    expect(booking.reload.duration_minutes).to eq(90)
    expect(booking).to be_duration_adjusted
    expect(booking.carrier_fee_cents).to eq(4_500)
  end

  it "fige d'emblée la durée prestée quand elle est posée avant la validation" do
    expect(tenue!(effective_duration: "1,5").carrier_fee_cents).to eq(4_500)
  end

  it "rend la main à la durée standard quand on la retape ou qu'on vide le champ" do
    booking = tenue!(effective_duration: "1h30")

    booking.update!(effective_duration: "2h")
    expect(booking.reload.duration_minutes).to be_nil
    expect(booking.carrier_fee_cents).to eq(6_000)

    booking.update!(effective_duration: "1h30")
    booking.update!(effective_duration: "")
    expect(booking.reload.duration_minutes).to be_nil
    expect(booking.carrier_fee_cents).to eq(6_000)
  end

  it "garde un montant posé à la main dans le même geste" do
    booking = tenue!
    booking.update!(effective_duration: "1h30", carrier_fee: "50")

    expect(booking.reload.carrier_fee_cents).to eq(5_000)
  end

  it "ne change pas le prix du séjour" do
    booking = tenue!
    expect { booking.update!(effective_duration: "1h30") }.not_to(change { booking.reload.price_cents })
  end

  it "refuse une durée illisible ou nulle" do
    booking = tenue!

    expect(booking.update(effective_duration: "longtemps")).to be(false)
    expect(booking.errors.full_messages.join).to include("Durée illisible")
    expect(booking.reload.update(effective_duration: "0")).to be(false)
  end

  it "lit les façons courantes d'écrire une durée" do
    {
      "1h30" => 90, "1 h 30" => 90, "1:30" => 90, "1h" => 60, "2h15min" => 135,
      "1,5" => 90, "1.25" => 75, "2" => 120, "90" => 90, "45 min" => 45, "" => nil
    }.each do |saisie, minutes|
      expect(described_class.parse_duration(saisie)).to eq(minutes), saisie
    end
    expect(described_class.parse_duration("bientôt")).to eq(:invalid)
    expect(described_class.format_duration(90)).to eq("1h30")
    expect(described_class.format_duration(45)).to eq("45 min")
  end

  it "le dit sur le relevé, puis fige la durée" do
    booking = tenue!(effective_duration: "1h30")
    statement = CarrierStatements::Generate.new(human: bene, period_from: Date.current - 30, period_to: Date.current).run!

    line = statement.carrier_statement_lines.first
    expect(line.label).to eq("Bain d'ânes (1h30, durée standard 2h)")
    expect(line.fee_cents).to eq(4_500)
    expect(booking.reload.update(effective_duration: "2h")).to be(false)
  end
end
