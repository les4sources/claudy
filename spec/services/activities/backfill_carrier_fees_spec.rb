require "rails_helper"

# Epic #244, phase 1 — la reprise des réservations déjà confirmées.
RSpec.describe Activities::BackfillCarrierFees do
  let(:carrier) { Human.create!(name: "Sébastien", email: "seb@les4sources.be") }
  let(:experience) do
    Experience.create!(name: "Initiation vannerie", human: carrier, duration_hours: 2,
                       fixed_price_cents: 0, price_cents: 2_500, min_participants: 1)
  end
  let(:stay) do
    Stay.create!(customer: Customer.create!(first_name: "Alice", last_name: "Martin",
                                            email: "alice@example.com"), status: "pending")
  end

  after { Pricing::Rates.reset! }

  # Une réservation confirmée AVANT cette phase : pas de montant figé.
  def legacy_booking(on: Date.new(2026, 3, 12))
    availability = ExperienceAvailability.create!(experience: experience, available_on: on,
                                                  starts_at: "10:00")
    booking = ExperienceBooking.create!(experience_availability: availability, stay: stay,
                                        participants: 2, status: "confirmed")
    booking.update_column(:carrier_fee_cents, nil)
    booking
  end

  it "complète les réservations confirmées restées sans montant" do
    booking = legacy_booking

    result = described_class.new(dry_run: false).run

    expect(booking.reload.carrier_fee_cents).to eq(8_000)
    expect(result.filled.size).to eq(1)
    expect(result.total_cents).to eq(8_000)
  end

  it "n'écrit rien en dry-run mais annonce ce qu'elle ferait" do
    booking = legacy_booking

    result = described_class.new.run

    expect(booking.reload.carrier_fee_cents).to be_nil
    expect(result.filled.size).to eq(1)
  end

  it "ne touche pas un montant déjà figé" do
    availability = ExperienceAvailability.create!(experience: experience,
                                                  available_on: Date.new(2026, 3, 12),
                                                  starts_at: "10:00")
    booking = ExperienceBooking.create!(experience_availability: availability, stay: stay,
                                        participants: 2, status: "confirmed")
    booking.update_column(:carrier_fee_cents, 1_234)

    described_class.new(dry_run: false).run

    expect(booking.reload.carrier_fee_cents).to eq(1_234)
  end

  it "ignore les réservations qui ne sont pas confirmées" do
    availability = ExperienceAvailability.create!(experience: experience,
                                                  available_on: Date.new(2026, 3, 12),
                                                  starts_at: "10:00")
    ExperienceBooking.create!(experience_availability: availability, stay: stay,
                              participants: 2, status: "pending")

    result = described_class.new(dry_run: false).run

    expect(result.filled).to be_empty
  end

  it "signale, sans rien inventer, les activités sans durée en heures" do
    booking = legacy_booking
    experience.update!(duration_hours: nil)

    result = described_class.new(dry_run: false).run

    expect(booking.reload.carrier_fee_cents).to be_nil
    expect(result.without_duration.size).to eq(1)
    expect(result.filled).to be_empty
  end

  it "applique le tarif de la DATE DU CRÉNEAU, pas celui d'aujourd'hui" do
    rate = Rate.create!(key: "activity.carrier_hourly", amount_cents: 5_000, label: "Porteur")
    rate.rate_versions.create!(amount_cents: 3_000, active_from: Date.new(2026, 1, 1),
                               active_until: Date.new(2026, 12, 31))
    Pricing::Rates.reset!
    booking = legacy_booking(on: Date.new(2026, 3, 12))

    described_class.new(dry_run: false).run

    expect(booking.reload.carrier_fee_cents).to eq(6_000)
  end

  it "est idempotente : relancer ne change plus rien" do
    legacy_booking
    described_class.new(dry_run: false).run

    result = described_class.new(dry_run: false).run

    expect(result.filled).to be_empty
  end
end
