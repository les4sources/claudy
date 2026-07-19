require "rails_helper"

# Issue #76 — action rapide de statut depuis la modale du calendrier. Le passage
# pending → confirmed propage aux réservables (veto de dispo cohérent) SANS
# envoyer d'email client, et répond en Turbo Stream (modale rafraîchie).
RSpec.describe "Stays — action rapide de statut (issue #76)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-quickstatus@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival)   { Date.today + 60 }
  let(:departure) { Date.today + 62 }

  def create_pending_stay
    draft = Reservations::Draft.new(
      lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure,
      adults: 2, dogs_count: 0, first_name: "Alice", last_name: "Martin",
      email: "alice@example.com", phone: "0470111222"
    )
    Reservations::Builder.new(draft: draft, admin: true, source: "manual", status: "pending").tap(&:run!).stay
  end

  it "confirme le séjour, propage au Booking et rend le veto cohérent — sans email" do
    stay = create_pending_stay
    booking = stay.stay_items.where(bookable_type: "Booking").first.bookable
    expect(stay.status).to eq("pending")
    expect(hulotte.available_between?(arrival, departure)).to be(true) # pending → libre

    expect {
      patch update_status_stay_path(stay), params: { status: "confirmed" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.not_to change { ActionMailer::Base.deliveries.count } # anti-spam : aucun email client

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(stay.reload.status).to eq("confirmed")
    expect(booking.reload.status).to eq("confirmed")
    # Veto désormais cohérent : le séjour confirmé bloque les chambres.
    expect(hulotte.available_between?(arrival, departure)).to be(false)
    # La modale rafraîchie porte le nouveau badge de statut.
    expect(response.body).to include("Confirmé")
  end

  it "repasse un séjour confirmé en attente (libère le veto)" do
    stay = create_pending_stay
    patch update_status_stay_path(stay), params: { status: "confirmed" }
    expect(hulotte.available_between?(arrival, departure)).to be(false)

    patch update_status_stay_path(stay), params: { status: "pending" }
    expect(stay.reload.status).to eq("pending")
    expect(hulotte.available_between?(arrival, departure)).to be(true)
  end

  it "refuse un statut invalide sans modifier le séjour" do
    stay = create_pending_stay
    patch update_status_stay_path(stay), params: { status: "canceled" }
    expect(stay.reload.status).to eq("pending")
  end
end
