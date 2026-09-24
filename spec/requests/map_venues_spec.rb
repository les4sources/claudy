require "rails_helper"

# Epic #348, phase 3 — la carte du jour : gîtes et salles reliés à leurs objets,
# occupation au jour choisi, panneau du groupe présent. Lecture seule.
RSpec.describe "Carte du domaine — carte du jour (epic #348, phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-jour@les4sources.be", password: "password123") }
  let(:venues) { MapLayer.for_kind(:venues) }
  let(:today) { Date.current }
  let(:square) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Mélisse", level: 1)
    lodging
  end
  let!(:grand_duc) do
    lodging = Lodging.create!(name: "Le Grand-Duc", price_night_cents: 90_000)
    LodgingComposition.create!(composite_lodging: lodging, component_lodging: hulotte)
    lodging
  end
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }

  def build_stay(arrival:, departure:, halls: [])
    draft = Reservations::Draft.new(
      lodging_id: hulotte.id, arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233", halls: halls
    )
    builder = Reservations::Builder.new(draft: draft, admin: true, status: "confirmed", source: "manual")
    builder.run!
    builder.stay
  end

  it "exige une session Devise" do
    get map_occupancy_path(format: :json)
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    it "la page carte ouvre la carte du jour, avec la couche des lieux et le sélecteur de date" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      get map_path(date: "2026-10-14")
      expect(response).to have_http_status(:ok)
      expect(MapLayer.where(kind: "venues").count).to eq(1)
      expect(response.body).to include("Hébergements et salles", "Jour suivant", %(data-map-date-value="2026-10-14"))
    end

    it "relie un tracé à un gîte, et un seul" do
      post map_features_path, headers: turbo, params: {
        map_feature: { map_layer_id: venues.id, geometry: square.to_json, feature_kind: "zone", linked_key: "Lodging:#{hulotte.id}" }
      }
      feature = MapFeature.last
      expect(feature.linked).to eq(hulotte)
      expect(feature.feature_kind).to eq("lodging")

      post map_features_path, headers: turbo, params: {
        map_feature: { map_layer_id: venues.id, geometry: square.to_json, linked_key: "Lodging:#{hulotte.id}" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("a déjà son tracé")
    end

    it "n'accepte comme liaison qu'un gîte ou une salle" do
      post map_features_path, headers: turbo, params: {
        map_feature: { map_layer_id: venues.id, geometry: square.to_json, linked_key: "User:#{user.id}" }
      }
      feature = MapFeature.last
      expect(feature.linked_type).to be_nil
      expect(feature.feature_kind).to eq("zone")
    end

    it "la fiche d'un tracé propose les gîtes non tracés, sans le gîte composite" do
      get new_map_feature_path(layer_id: venues.id, feature_kind: "zone")
      expect(response.body).to include("La Hulotte", "Grande Salle")
      expect(response.body).not_to include("Le Grand-Duc")
    end

    it "liste les gîtes et salles restant à tracer" do
      get map_venues_todo_path
      expect(response.body).to include("À tracer", "La Hulotte", "Grande Salle")
      expect(response.body).not_to include("Le Grand-Duc")

      venues.map_features.create!(geometry: square, linked_key: "Lodging:#{hulotte.id}")
      venues.map_features.create!(geometry: square, linked_key: "Space:#{grande_salle.id}")
      get map_venues_todo_path
      expect(response.body).not_to include("À tracer")
    end

    it "renvoie l'occupation du jour par objet" do
      feature = venues.map_features.create!(geometry: square, linked_key: "Lodging:#{hulotte.id}")
      build_stay(arrival: today - 1, departure: today + 2)

      get map_occupancy_path(format: :json, date: today.iso8601)
      states = response.parsed_body["states"]
      expect(states[feature.id.to_s]).to eq("state" => "occupied", "label" => "Occupé")

      get map_occupancy_path(format: :json, date: (today + 2).iso8601)
      expect(response.parsed_body["states"][feature.id.to_s]["state"]).to eq("turnover")
    end

    it "une date illisible retombe sur aujourd'hui" do
      get map_occupancy_path(format: :json, date: "n'importe quoi")
      expect(response.parsed_body["date"]).to eq(today.iso8601)
    end

    it "le panneau d'un gîte occupé montre le groupe présent et le lien vers le séjour" do
      feature = venues.map_features.create!(geometry: square, linked_key: "Lodging:#{hulotte.id}")
      stay = build_stay(arrival: today, departure: today + 2)
      stay.update_columns(notes: "Clé sous le pot de romarin") if stay.has_attribute?(:notes)

      get map_venue_path(feature, date: today.iso8601)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Carte du jour", "La Hulotte", "Camille Martin", "Arrive aujourd'hui",
                                       "Ouvrir le séjour", stay_path(stay))
    end

    it "le panneau d'un gîte libre annonce le prochain séjour" do
      feature = venues.map_features.create!(geometry: square, linked_key: "Lodging:#{hulotte.id}")
      build_stay(arrival: today + 3, departure: today + 5)

      get map_venue_path(feature, date: today.iso8601)
      expect(response.body).to include("Libre", "Prochain séjour", "Camille Martin")
    end

    it "le panneau d'une salle montre la réservation du jour et son créneau" do
      feature = venues.map_features.create!(geometry: square, linked_key: "Space:#{grande_salle.id}")
      build_stay(arrival: today, departure: today + 1,
                 halls: [{ kind: "grande_salle", date: today.iso8601, period: "journee" }])

      get map_venue_path(feature, date: today.iso8601)
      expect(response.body).to include("Grande Salle", "Camille Martin", "Créneau")
    end

    it "ne modifie aucun séjour en consultant la carte" do
      feature = venues.map_features.create!(geometry: square, linked_key: "Lodging:#{hulotte.id}")
      stay = build_stay(arrival: today, departure: today + 2)
      expect {
        get map_venue_path(feature, date: today.iso8601)
        get map_occupancy_path(format: :json, date: today.iso8601)
      }.not_to(change { [stay.reload.updated_at, Booking.maximum(:updated_at), Reservation.count] })
    end
  end
end
