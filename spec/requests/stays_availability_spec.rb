require "rails_helper"

# Issue #77 — endpoint de disponibilité en temps réel du form Séjour admin.
# Réutilise `Lodging#available_between?` (source unique de vérité). Informe sans
# bloquer : c'est un simple JSON { available: bool } consommé par le form.
RSpec.describe "Stays — disponibilité temps réel (issue #77)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-availability@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def get_availability(overrides = {})
    get availability_stays_path, params: {
      lodging_id: hulotte.id, arrival_date: arrival.iso8601, departure_date: departure.iso8601
    }.merge(overrides)
    JSON.parse(response.body)
  end

  it "renvoie available: true hors chevauchement" do
    body = get_availability
    expect(response).to have_http_status(:ok)
    expect(body["checkable"]).to be(true)
    expect(body["available"]).to be(true)
    expect(body["lodging"]).to eq("La Hulotte")
  end

  it "renvoie available: false sur un chevauchement confirmé" do
    occ = Booking.create!(firstname: "Occ", from_date: arrival, to_date: departure, adults: 1, status: "confirmed")
    (arrival..departure).each { |d| Reservation.create!(booking: occ, room: hulotte.rooms.first, date: d) }

    body = get_availability
    expect(body["checkable"]).to be(true)
    expect(body["available"]).to be(false)
  end

  it "renvoie checkable: false sans hébergement ou sans dates" do
    expect(get_availability(lodging_id: "")["checkable"]).to be(false)
    expect(get_availability(arrival_date: "")["checkable"]).to be(false)
  end

  it "renvoie checkable: false si départ avant arrivée" do
    expect(get_availability(departure_date: (arrival - 1).iso8601)["checkable"]).to be(false)
  end

  it "le form new câble l'indicateur de disponibilité (data-controller + target)" do
    get new_stay_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("stay-availability")
    expect(response.body).to include("stay-availability-target=\"indicator\"")
    expect(response.body).to include(availability_stays_path)
  end
end
