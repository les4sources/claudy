require "rails_helper"

# Slice C — le form admin lit désormais `stay[lodging_night_ids][]` (grille
# hébergement nuit par nuit, parité funnel) et `stay[spaces_note]` (précision du
# besoin d'espace). Ce spec verrouille le round-trip contrôleur → Builder →
# persistance → DraftReconstructor.
RSpec.describe "Stays — round-trip lodging_night_ids + spaces_note", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-rt@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte)      { Lodging.create!(name: "La Hulotte", summary: "gîte").tap { |l| l.rooms << Room.create!(name: "Ch1", level: 1) } }
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 4) }
  let(:arrival)       { Date.today + 30 }
  let(:departure)     { Date.today + 32 } # 2 nuits

  def create_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice-rt@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0, status: "pending"
      }.merge(overrides)
    }
  end

  it "persiste l'hébergement choisi via lodging_night_ids et le reconstruit" do
    post stays_path, params: create_params(lodging_night_ids: [hulotte.id.to_s, hulotte.id.to_s])
    expect(response).to redirect_to(recent_stays_path)

    stay = Stay.order(:created_at).last
    booking = stay.stay_items.where(bookable_type: "Booking").first&.bookable
    expect(booking).to be_present
    expect(booking.lodging_id).to eq(hulotte.id)

    draft = Stays::DraftReconstructor.call(stay)
    expect(draft.lodging_night_ids).to eq([hulotte.id.to_s, hulotte.id.to_s])
  end

  it "range spaces_note dans la note interne préfixée du SpaceBooking, et la reconstruit" do
    post stays_path, params: create_params(
      halls: { "0" => { kind: "grande_salle", date: arrival.iso8601, period: "journee" } },
      spaces_note: "Arrivée vendredi 17h, besoin de 60 chaises."
    )
    expect(response).to redirect_to(recent_stays_path)

    stay = Stay.order(:created_at).last
    sb = stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
    expect(sb.notes).to include("Arrivée vendredi 17h, besoin de 60 chaises.")

    draft = Stays::DraftReconstructor.call(stay)
    expect(draft.spaces_note).to eq("Arrivée vendredi 17h, besoin de 60 chaises.")
  end
end
