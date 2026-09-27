require "rails_helper"

# Issue #370 — un tracé peut représenter plusieurs gîtes ou salles : la
# Chevêche au rez-de-chaussée et la Hulotte à l'étage du même bâtiment. Le
# Grand-Duc (composite des deux) reste hors de la carte.
RSpec.describe "Carte du domaine — un tracé, plusieurs lieux (issue #370)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-multi@les4sources.be", password: "password123") }
  let(:venues) { MapLayer.for_kind(:venues) }
  let(:today) { Date.current }
  let(:square) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let!(:cheveche) do
    lodging = Lodging.create!(name: "La Chevêche", price_night_cents: 42_000)
    lodging.rooms << Room.create!(name: "Sauge", level: 0)
    lodging
  end
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Mélisse", level: 1)
    lodging
  end
  let!(:grand_duc) do
    lodging = Lodging.create!(name: "Le Grand-Duc", price_night_cents: 90_000)
    LodgingComposition.create!(composite_lodging: lodging, component_lodging: cheveche)
    LodgingComposition.create!(composite_lodging: lodging, component_lodging: hulotte)
    lodging
  end
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }
  let(:building_keys) { ["Lodging:#{cheveche.id}", "Lodging:#{hulotte.id}"] }

  def building = venues.map_features.create!(geometry: square, venue_keys: building_keys)

  def build_stay(lodging, arrival: today + 10, departure: today + 12, email: "camille@example.com", last_name: "Martin")
    draft = Reservations::Draft.new(
      lodging_id: lodging.id, arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: last_name,
      email: email, phone: "+32470112233", halls: []
    )
    builder = Reservations::Builder.new(draft: draft, admin: true, status: "confirmed", source: "manual")
    builder.run!
    builder.stay
  end

  context "connecté" do
    before { sign_in user }

    it "crée un tracé avec plusieurs lieux cochés, puis les décoche tous" do
      post map_features_path, headers: turbo, params: {
        map_feature: { map_layer_id: venues.id, geometry: square.to_json, feature_kind: "zone", venue_keys: [""] + building_keys }
      }
      expect(response).to have_http_status(:ok)
      feature = MapFeature.last
      expect(feature.venues).to eq([cheveche, hulotte])
      expect(feature.feature_kind).to eq("lodging")
      expect(response.body).to include("La Chevêche · La Hulotte")

      patch map_feature_path(feature), headers: turbo, params: {
        map_feature: { venue_keys: ["", "Lodging:#{hulotte.id}", "Space:#{grande_salle.id}"] }
      }
      expect(feature.reload.venues).to eq([hulotte, grande_salle])

      patch map_feature_path(feature), headers: turbo, params: { map_feature: { venue_keys: [""] } }
      expect(feature.reload.venues).to be_empty
      expect(feature.feature_kind).to eq("zone")
    end

    it "une fiche sans champ des lieux ne touche pas aux liaisons" do
      feature = building
      patch map_feature_path(feature), headers: turbo, params: { map_feature: { name: "Le bâtiment" } }
      expect(feature.reload.venues).to eq([cheveche, hulotte])
    end

    it "refuse un gîte déjà tracé ailleurs, avec son nom" do
      building
      post map_features_path, headers: turbo, params: {
        map_feature: { map_layer_id: venues.id, geometry: square.to_json, venue_keys: ["", "Lodging:#{hulotte.id}"] }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("La Hulotte a déjà son tracé sur la carte")
    end

    it "la fiche coche ce que le tracé représente et propose ce qui reste à tracer, groupé" do
      feature = building
      get map_feature_path(feature)
      page = Nokogiri::HTML(response.body)
      boxes = page.css("input[type=checkbox][name='map_feature[venue_keys][]']")
      expect(boxes.map { |b| b["value"] }).to contain_exactly(*building_keys, "Space:#{grande_salle.id}")
      expect(boxes.select { |b| b["checked"] }.map { |b| b["value"] }).to match_array(building_keys)
      expect(page.css("input[type=hidden][name='map_feature[venue_keys][]']").map { |i| i["value"] }).to eq([""])
      expect(response.body).to include("Gîtes et salles représentés", "Gîtes", "Salles et espaces")
      expect(response.body).not_to include("Le Grand-Duc")

      get new_map_feature_path(layer_id: venues.id, feature_kind: "zone")
      values = Nokogiri::HTML(response.body).css("input[type=checkbox]").map { |b| b["value"] }
      expect(values).to eq(["Space:#{grande_salle.id}"])
    end

    it "« À tracer » ne montre plus ni la Chevêche, ni la Hulotte, ni le Grand-Duc" do
      building
      get map_venues_todo_path
      expect(response.body).to include("Grande Salle")
      expect(response.body).not_to include("La Chevêche", "La Hulotte", "Le Grand-Duc")
    end

    it "un tracé supprimé rend ses gîtes à « À tracer »" do
      feature = building
      delete map_feature_path(feature), headers: turbo
      get map_venues_todo_path
      expect(response.body).to include("La Chevêche", "La Hulotte")
      expect(response.body).not_to include("Le Grand-Duc")
    end

    it "la carte du jour donne l'état le plus actif et le détail par gîte" do
      feature = building
      build_stay(hulotte, arrival: today, departure: today + 2)

      get map_occupancy_path(format: :json, date: today.iso8601)
      expect(response.parsed_body["states"][feature.id.to_s])
        .to eq("state" => "turnover", "label" => "La Chevêche : Libre · La Hulotte : Arrivée")
    end

    it "le panneau du jour a une section par gîte, dans l'ordre" do
      feature = building
      build_stay(hulotte, arrival: today, departure: today + 2)
      build_stay(cheveche, arrival: today + 3, departure: today + 5, email: "alex@example.com", last_name: "Dupont")

      get map_venue_path(feature, date: today.iso8601)
      expect(response).to have_http_status(:ok)
      sections = Nokogiri::HTML(response.body).css("[data-venue-section]")
      expect(sections.map { |s| s["data-venue-section"] }).to eq(["La Chevêche", "La Hulotte"])
      expect(sections[0].text).to include("Libre", "Prochain séjour", "Camille Dupont")
      expect(sections[1].text).to include("Camille Martin", "Arrive aujourd'hui")
    end

    it "un tracé à un seul gîte garde son panneau d'avant, sans section" do
      feature = venues.map_features.create!(geometry: square, venue_keys: ["Lodging:#{hulotte.id}"])
      get map_venue_path(feature, date: today.iso8601)
      expect(response.body).to include("La Hulotte", "Libre")
      expect(Nokogiri::HTML(response.body).css("[data-venue-section]")).to be_empty
    end

    it "le GeoJSON d'un tracé sans nom propre porte les noms de ses lieux" do
      feature = building
      get map_features_path(format: :json, layer_id: venues.id)
      props = response.parsed_body["features"].find { |f| f["id"] == feature.id }["properties"]
      expect(props).to include("name" => "La Chevêche · La Hulotte", "feature_kind" => "lodging")
      expect(props["venue_keys"]).to match_array(building_keys)
    end
  end

  describe "la page publique du séjour" do
    before do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20, default: true,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      building
    end

    def lodging_labels(stay)
      get public_stay_map_path(stay.token)
      node = Nokogiri::HTML(response.body).at_css("[data-controller='public--stay-map']")
      JSON.parse(node["data-public--stay-map-lodgings-value"])["features"].map { |f| f["properties"]["name"] }
    end

    it "un séjour à la Hulotte surligne le bâtiment, étiqueté « La Hulotte » seulement" do
      expect(lodging_labels(build_stay(hulotte))).to eq(["La Hulotte"])
      expect(response.body).not_to include("La Chevêche")
    end

    it "un séjour au Grand-Duc surligne le bâtiment « La Chevêche · La Hulotte »" do
      expect(lodging_labels(build_stay(grand_duc))).to eq(["La Chevêche · La Hulotte"])
    end
  end
end
