require "rails_helper"

# Epic #81, Phase 4 — Absorber l'OTA (Airbnb / Booking.com) dans le séjour.
#
# Un séjour OTA se crée avec une plateforme (Airbnb / Booking.com) et un PRIX
# LIBRE (le montant de la plateforme, saisi via `price_override`). Il occupe le
# calendrier et pose le veto de disponibilité EXACTEMENT comme un séjour B2C :
# c'est `Reservations::Builder` (mode admin) qui crée les `Reservation` de
# chambres jour par jour (fix epic #66, Phase 6). On le PROUVE ici de bout en
# bout — création, Reservation, veto Grand-Duc, rendu calendrier, prefill edit.
RSpec.describe "Stays — canal OTA (epic #81, Phase 4)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-ota@les4sources.be", password: "password123") }
  before { sign_in user }

  # La Hulotte est au barème B2C (Pricing::Catalog) ET porte une chambre : c'est
  # la chambre qui reçoit les `Reservation` jour par jour — source de vérité du
  # veto (`Lodging#available_between?`) et du rendu calendrier par ressource.
  let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let!(:room)    { lodging.rooms.create!(name: "Chambre Hulotte", level: 1) }
  let(:arrival)   { Date.today.next_occurring(:friday) }
  let(:departure) { arrival + 2 } # 2 nuits → 2 Reservation attendues

  # Teinte séjour attendue au calendrier — même formule que CalendarHelper.
  def hue_for(stay_id)
    ((stay_id * CalendarHelper::GOLDEN_ANGLE) % 360).round
  end

  def ota_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Olga", last_name: "Airbnb", email: "olga@example.com", phone: "0470999888" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: lodging.id, status: "confirmed",
        source: "ota", platform: "airbnb", price_override: "640"
      }.merge(overrides)
    }
  end

  def last_booking
    Stay.order(:created_at).last.stay_items.where(bookable_type: "Booking").first.bookable
  end

  describe "création d'un séjour OTA complet (AC1 / AC4)" do
    it "enregistre source ota, plateforme persistée et total = prix imposé" do
      expect {
        post stays_path, params: ota_params
      }.to change(Stay, :count).by(1)
       .and change(Booking, :count).by(1)
       .and change(Customer, :count).by(1)

      expect(response).to redirect_to(recent_stays_path)
      stay = Stay.order(:created_at).last
      expect(stay.source).to eq("ota")
      expect(stay.status).to eq("confirmed")
      expect(stay.price_override_cents).to eq(64_000)
      expect(stay.total_amount_cents).to eq(64_000)          # prix imposé, pas le devis B2C (74 500)
      expect(last_booking.platform).to eq("airbnb")
      # Canal admin : aucun paiement (donc aucun Stripe) à la création.
      expect(stay.payments).to be_empty
    end

    it "absorbe aussi Booking.com comme plateforme" do
      post stays_path, params: ota_params(platform: "bookingdotcom")
      expect(last_booking.platform).to eq("bookingdotcom")
    end
  end

  describe "occupation calendrier & veto de disponibilité (AC3)" do
    it "crée les Reservation de chambres jour par jour sur la fenêtre" do
      post stays_path, params: ota_params

      booking = last_booking
      # 2 nuits [arrivée, départ) → une Reservation par nuit sur la chambre.
      expect(booking.reservations.count).to eq(2)
      expect(booking.reservations.pluck(:date)).to match_array([arrival, arrival + 1])
      expect(booking.reservations.pluck(:room_id).uniq).to eq([room.id])
    end

    it "pose le veto : l'hébergement n'est plus disponible sur la fenêtre" do
      post stays_path, params: ota_params

      # Même sémantique que le veto du Builder (`available_between?(arrivée, départ)`).
      expect(lodging.reload.available_between?(arrival, departure)).to be(false)
      expect(lodging.available_on?(arrival)).to be(false)
    end

    it "refuse un 2e séjour sur le même hébergement / mêmes dates sans forçage" do
      post stays_path, params: ota_params # 1er séjour OTA confirmé → pose le veto

      expect {
        post stays_path, params: ota_params(
          source: "manual", platform: "web",
          new_customer: { first_name: "Bob", last_name: "Direct", email: "bob@example.com", phone: "0470000000" }
        )
      }.not_to change(Stay, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("plus disponibles")
    end

    it "autorise le 2e séjour en forçant la disponibilité (surbooking)" do
      post stays_path, params: ota_params

      expect {
        post stays_path, params: ota_params(
          force_availability: "1",
          new_customer: { first_name: "Bob", last_name: "Direct", email: "bob@example.com", phone: "0470000000" }
        )
      }.to change(Stay, :count).by(1)

      expect(response).to redirect_to(recent_stays_path)
      expect(flash[:alert]).to include("forçant la disponibilité")
    end

    it "apparaît au calendrier, groupé et teinté par séjour (data-stay-id)" do
      post stays_path, params: ota_params
      stay    = Stay.order(:created_at).last
      booking = last_booking

      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-stay-id=\"#{stay.id}\"")
      # 2 nuits → 2 entrées jour chambre (la représentation qui porte le veto).
      expect(response.body.scan("data-booking-day-entry=\"#{booking.id}\"").size).to eq(2)
      expect(response.body).to include("hsl(#{hue_for(stay.id)}, 65%, 45%)")
    end
  end

  describe "édition d'un séjour OTA — prefill (AC4)" do
    it "présélectionne la plateforme, le canal OTA et préremplit le prix imposé" do
      post stays_path, params: ota_params
      stay = Stay.order(:created_at).last

      get edit_stay_path(stay)

      expect(response).to have_http_status(:ok)
      # Plateforme Airbnb présélectionnée dans le <select>.
      expect(response.body).to match(/<option selected[^>]*value="airbnb"|<option[^>]*value="airbnb"[^>]*selected/)
      # Canal OTA présélectionné.
      expect(response.body).to match(/<option selected[^>]*value="ota"|<option[^>]*value="ota"[^>]*selected/)
      # Prix imposé prérempli (640 €).
      expect(response.body).to include('value="640"')
    end
  end
end
