require "rails_helper"

# Rétablir une activité retirée par erreur (Michael, 2026-10-19) : elle reprend
# le statut qu'elle avait avant le retrait, d'après l'historique PaperTrail.
RSpec.describe ExperienceBooking, "#restore!", type: :model do
  let(:customer) { Customer.create!(email: "retablir@example.com", customer_type: "individual") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "confirmed", arrival_date: Date.today - 9, departure_date: Date.today - 7) }
  let(:porteuse) { Human.create!(name: "Béné", email: "bene-retablir@example.com") }
  let(:anes) { Experience.create!(name: "Rencontre avec les ânes", human: porteuse, fixed_price_cents: 12_000, duration_hours: 2, max_participants: 12) }
  let(:creneau) { ExperienceAvailability.create!(experience: anes, available_on: Date.today - 8, starts_at: "14:00") }

  it "remet une activité tenue puis retirée en confirmée, verdict et rémunération intacts" do
    resa = ExperienceBooking.create!(experience_availability: creneau, stay: stay, participants: 12, status: "confirmed")
    resa.mark_held!
    fee = resa.reload.carrier_fee_cents
    resa.update!(status: "cancelled")

    resa.restore!

    expect(resa.reload).to have_attributes(status: "confirmed", outcome: "held", carrier_fee_cents: fee)
  end

  it "remet une activité à valider en « à valider »" do
    resa = ExperienceBooking.create!(experience_availability: creneau, stay: stay, participants: 2, status: "pending")
    resa.update!(status: "cancelled")

    resa.restore!

    expect(resa.reload).to be_pending
  end

  it "rétablit même si le créneau est désormais complet" do
    resa = ExperienceBooking.create!(experience_availability: creneau, stay: stay, participants: 12, status: "confirmed")
    resa.update!(status: "cancelled")
    ExperienceBooking.create!(experience_availability: creneau, stay: stay, participants: 12, status: "confirmed")

    expect { resa.restore! }.not_to raise_error
    expect(resa.reload).to be_confirmed
  end

  it "sans historique, une activité déjà tenue repart confirmée" do
    resa = PaperTrail.request(enabled: false) do
      ExperienceBooking.create!(experience_availability: creneau, stay: stay, participants: 2, status: "cancelled", outcome: "held")
    end

    expect(resa.status_before_cancellation).to eq("confirmed")
  end

  it "refuse une activité qui n'est pas retirée" do
    resa = ExperienceBooking.create!(experience_availability: creneau, stay: stay, participants: 2, status: "confirmed")

    expect { resa.restore! }.to raise_error(ExperienceBooking::NotRestorable)
  end
end
