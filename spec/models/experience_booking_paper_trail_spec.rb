require "rails_helper"

# Audit (epic #81) : ExperienceBooking est rapatrié par la fusion de séjours ;
# il lui faut un historique PaperTrail comme aux autres modèles migrés.
RSpec.describe ExperienceBooking, type: :model do
  let(:customer) { Customer.create!(email: "eb@example.com", customer_type: "individual") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "confirmed", arrival_date: Date.today + 5, departure_date: Date.today + 7) }
  let(:other_stay) { Stay.create!(customer: customer, source: "manual", status: "confirmed", arrival_date: Date.today + 10, departure_date: Date.today + 12) }
  let(:porteur) { Human.create!(name: "Porteur", email: "porteur-eb@example.com") }
  let(:experience) { Experience.create!(name: "Balade", human: porteur, fixed_price_cents: 4_000, price_cents: 1_500) }
  let(:availability) { ExperienceAvailability.create!(experience: experience, available_on: Date.today + 6, starts_at: "10:00") }

  it "est versionné par PaperTrail" do
    expect(described_class).to respond_to(:paper_trail)
    eb = ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "confirmed")
    expect(eb.versions).to be_present # au moins la version de création
  end

  it "trace un changement de stay_id (rattachement à un autre séjour, cas fusion)" do
    eb = ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "confirmed")
    expect { eb.update!(stay_id: other_stay.id) }.to change { eb.versions.count }.by(1)
    expect(eb.versions.last.object_changes).to include("stay_id")
  end
end
