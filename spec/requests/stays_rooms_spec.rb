require "rails_helper"

# Epic #81, Phase 5 — CRUD Séjour admin en mode CHAMBRES SEULES + endpoint de
# disponibilité par chambres. Parité avec le gîte entier, DANS le séjour.
RSpec.describe "Stays — chambres seules (epic #81, Phase 5)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-rooms@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", summary: "gîte", price_night_cents: 48_500)
    lodging.rooms << (@room_1 = Room.create!(name: "Chambre 1", level: 1))
    lodging.rooms << (@room_2 = Room.create!(name: "Chambre 2", level: 1))
    lodging.rooms << (@room_3 = Room.create!(name: "Chambre 3", level: 2))
    lodging
  end

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: hulotte.id, status: "confirmed"
      }.merge(overrides)
    }
  end

  def booking_of(stay)
    stay.stay_items.where(bookable_type: "Booking").first.bookable
  end

  describe "GET /stays/new" do
    it "affiche le mode chambres seules et les chambres du gîte" do
      get new_stay_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="rooms"')
      expect(response.body).to include("Chambres seules")
      expect(response.body).to include('name="stay[room_ids][]"')
      expect(response.body).to include("Chambre 1")
    end
  end

  describe "POST /stays (création chambres seules)" do
    it "crée un séjour chambres seules avec 2 chambres sur 3 et le prix imposé" do
      post stays_path, params: base_params(
        booking_type: "rooms",
        room_ids: [@room_1.id, @room_2.id],
        price_override: "150"
      )
      expect(response).to redirect_to(recent_stays_path)

      stay = Stay.order(:created_at).last
      booking = booking_of(stay)
      # booking_type est un attr_accessor non persisté → on vérifie le mode par les
      # Reservation (source de vérité, cf. Booking#rooms_only_occupation?).
      expect(booking.rooms_only_occupation?).to be(true)
      expect(booking.reservations.map(&:room_id).uniq).to match_array([@room_1.id, @room_2.id])
      expect(booking.reservations.count).to eq(4) # 2 chambres × 2 nuits
      expect(stay.total_amount_cents).to eq(15_000) # override, pas de forfait gîte
    end

    it "refuse un séjour chambres seules sans chambre cochée" do
      expect {
        post stays_path, params: base_params(booking_type: "rooms", room_ids: [])
      }.not_to change(Stay, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("au moins une chambre")
    end

    it "affiche le message « pas de devis automatique » via le devis live" do
      post quote_stays_path, params: base_params(booking_type: "rooms", room_ids: [@room_1.id]), as: :turbo_stream
      expect(response.body).to include("Pas de devis automatique pour des chambres seules")
    end
  end

  describe "veto croisé (endpoint availability)" do
    def get_availability(overrides = {})
      get availability_stays_path, params: {
        lodging_id: hulotte.id, arrival_date: arrival.iso8601, departure_date: departure.iso8601
      }.merge(overrides)
      JSON.parse(response.body)
    end

    it "chambre libre → available:true ; chambre prise → available:false (granulaire)" do
      # Occupe la chambre 1 (confirmée) via un séjour chambres seules.
      post stays_path, params: base_params(booking_type: "rooms", room_ids: [@room_1.id], price_override: "100")

      taken = get_availability(booking_type: "rooms", "room_ids[]": [@room_1.id])
      free  = get_availability(booking_type: "rooms", "room_ids[]": [@room_2.id])
      expect(taken["available"]).to be(false)
      expect(free["available"]).to be(true)
    end

    it "un gîte entier confirmé rend TOUTES ses chambres indisponibles" do
      post stays_path, params: base_params(booking_type: "lodging")

      body = get_availability(booking_type: "rooms", "room_ids[]": [@room_2.id])
      expect(body["available"]).to be(false)
    end

    it "checkable:false en mode rooms sans chambre transmise" do
      expect(get_availability(booking_type: "rooms")["checkable"]).to be(false)
    end
  end

  describe "PATCH /stays/:id (édition chambres seules)" do
    it "prérempli le mode chambres et change les chambres réservées" do
      post stays_path, params: base_params(booking_type: "rooms", room_ids: [@room_1.id], price_override: "100")
      stay = Stay.order(:created_at).last

      # Le form d'édition restitue le mode chambres + la chambre cochée.
      get edit_stay_path(stay)
      expect(response.body).to include('value="rooms"')
      # Slim ordonne les attributs alphabétiquement : checked="" … value="ID".
      expect(response.body).to match(/<input checked[^>]*name="stay\[room_ids\]\[\]"[^>]*value="#{@room_1.id}"/)

      patch stay_path(stay), params: {
        stay: {
          customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: hulotte.id, status: "confirmed",
          booking_type: "rooms", room_ids: [@room_2.id, @room_3.id], price_override: "100"
        }
      }
      expect(response).to redirect_to(recent_stays_path)

      booking = booking_of(stay.reload)
      expect(booking.reservations.map(&:room_id).uniq).to match_array([@room_2.id, @room_3.id])
    end
  end
end
