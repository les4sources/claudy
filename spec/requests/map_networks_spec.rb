require "rails_helper"

# Epic #348, phase 9 — les réseaux : nœuds (vannes, tableaux, switchs…) et
# tracés, par les endpoints existants des objets de la carte.
RSpec.describe "Carte du domaine — réseaux (epic #348, phase 9)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-reseaux@les4sources.be", password: "password123") }
  let(:water) { MapLayer.ensure_networks!.first }
  let(:point) { { "type" => "Point", "coordinates" => [4.905, 50.340] } }
  let(:line) { { "type" => "LineString", "coordinates" => [[4.905, 50.340], [4.906, 50.340]] } }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:json) { { "Accept" => "application/json" } }

  before { sign_in user }

  it "la page carte garantit les quatre couches réseau et les liste dans la section Réseaux" do
    MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                         bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
    get map_path
    expect(response).to have_http_status(:ok)
    expect(MapLayer.where(kind: "network").map(&:network)).to contain_exactly("water", "electric", "ethernet", "gas")
    expect(response.body).to include("data-map-networks-section", "Électricité", "Ethernet", "Gaz")
    # Une couche à la fois : plus de sélecteur « n'afficher qu'un réseau ».
    expect(response.body).not_to include("Tous les réseaux")
    expect(response.body).to include('data-network="water"', 'data-network-color="#2563EB"')
  end

  it "sert la fiche d'un nouveau nœud avec les types du réseau et la consigne" do
    get new_map_feature_path(layer_id: water.id, feature_kind: "node")
    expect(response.body).to include("Type de nœud", "Vanne", "Regard", "Consigne", "UniFi")
    expect(response.body).not_to include("Disjoncteur")
  end

  it "crée un nœud avec son type, sa consigne et son équipement" do
    post map_features_path, headers: turbo, params: {
      map_feature: { map_layer_id: water.id, feature_kind: "node", geometry: point.to_json, name: "Vanne du gîte",
                     node_type: "valve", instructions: "  Quart de tour vers la droite  ", equipment: "" }
    }
    expect(response).to have_http_status(:ok)
    node = MapFeature.last
    expect(node.properties).to include("node_type" => "valve", "instructions" => "Quart de tour vers la droite")
    expect(node.properties).not_to have_key("equipment")
    expect(response.body).to include("Quart de tour vers la droite", "Consigne")
  end

  it "met à jour la consigne et l'équipement d'un nœud" do
    node = water.map_features.create!(feature_kind: "node", geometry: point, properties: { "node_type" => "valve" })
    patch map_feature_path(node), headers: turbo,
                                  params: { map_feature: { instructions: "Fermer la vanne rouge", equipment: "unifi" } }
    expect(node.reload.properties).to include("node_type" => "valve", "instructions" => "Fermer la vanne rouge",
                                              "equipment" => "unifi")
  end

  # Les répartiteurs d'abord classés en vannes se reclassent depuis la fiche.
  it "reclasse une vanne en répartiteur, consigne gardée" do
    node = water.map_features.create!(feature_kind: "node", geometry: point,
                                      properties: { "node_type" => "valve", "instructions" => "Trois départs" })
    get map_feature_path(node)
    expect(response.body).to include(%(<option value="manifold">Répartiteur</option>))
    patch map_feature_path(node), headers: turbo, params: { map_feature: { node_type: "manifold" } }
    expect(node.reload.properties).to include("node_type" => "manifold", "instructions" => "Trois départs")
    expect(node.node_type_label).to eq("Répartiteur")
  end

  it "refuse un type de nœud d'un autre réseau" do
    post map_features_path, headers: json, params: {
      map_feature: { map_layer_id: water.id, feature_kind: "node", geometry: point.to_json, node_type: "breaker" }
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["errors"].join).to include("breaker")
  end

  it "crée un tracé avec son calibre, et le JSON porte réseau, calibre et longueur" do
    post map_features_path, headers: json, params: {
      map_feature: { map_layer_id: water.id, feature_kind: "line", geometry: line.to_json, gauge: "thick" }
    }
    expect(response).to have_http_status(:created)
    props = JSON.parse(response.body)["properties"]
    expect(props).to include("feature_kind" => "line", "network" => "water", "gauge" => "thick", "color" => "#2563EB")
    expect(props["length_m"]).to be_within(1).of(71)

    get map_features_path(format: :json, layer_id: water.id)
    expect(JSON.parse(response.body)["features"].first["properties"]).to include("network" => "water")
  end

  it "affiche la longueur calculée d'un tracé et son calibre dans la fiche" do
    trace = water.map_features.create!(feature_kind: "line", geometry: line, description_i18n: { "fr" => "PE 32" })
    get map_feature_path(trace)
    expect(response.body).to include("Longueur", "71 m", "Calibre", "Moyen", "Notes", "PE 32")
    expect(response.body).not_to include("Type de nœud")
  end

  it "met en avant la consigne dans la fiche d'un nœud" do
    node = water.map_features.create!(feature_kind: "node", geometry: point,
                                      properties: { "node_type" => "valve", "instructions" => "Quart de tour" })
    get map_feature_path(node)
    expect(response.body).to include("data-network-instructions", "Quart de tour", "Eau")
    expect(response.body).not_to include("Longueur")
  end
  describe "origine de l'eau d'un robinet" do
    it "la fiche d'un robinet propose l'origine de l'eau, masquée pour un autre type" do
      tap = water.map_features.create!(feature_kind: "node", geometry: point, properties: { "node_type" => "tap" })
      get map_feature_path(tap)
      expect(response.body).to include("Origine de l’eau", "Eau de pluie", "Captage forestier", "Eau de puits")
      expect(response.body).not_to match(/<div(?=[^>]*\bhidden)[^>]*data-water-source-field/)

      valve = water.map_features.create!(feature_kind: "node", geometry: point, properties: { "node_type" => "valve" })
      get map_feature_path(valve)
      expect(response.body).to match(/<div(?=[^>]*\bhidden)[^>]*data-water-source-field/)
    end

    it "enregistre l'origine d'un robinet et la porte dans le JSON" do
      post map_features_path, headers: json, params: {
        map_feature: { map_layer_id: water.id, feature_kind: "node", geometry: point.to_json, name: "Robinet du potager",
                       node_type: "tap", water_source: "rain" }
      }
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["properties"]).to include("water_source" => "rain",
                                                                 "water_source_label" => "Eau de pluie",
                                                                 "non_potable" => true)
    end

    it "signale non potables la pluie et le captage forestier, pas le puits, sur la carte comme dans la fiche" do
      well = water.map_features.create!(feature_kind: "node", geometry: point,
                                        properties: { "node_type" => "tap", "water_source" => "well" })
      rain = water.map_features.create!(feature_kind: "node", geometry: point,
                                        properties: { "node_type" => "tap", "water_source" => "rain" })
      catchment = water.map_features.create!(feature_kind: "node", geometry: point,
                                             properties: { "node_type" => "tap", "water_source" => "forest_catchment" })
      expect(well.as_geojson[:properties]).not_to have_key(:non_potable)
      expect(catchment.as_geojson[:properties]).to include(non_potable: true)

      get map_feature_path(well)
      expect(response.body).to match(/<p(?=[^>]*\bhidden)[^>]*data-non-potable-hint/)
      get map_feature_path(rain)
      expect(response.body).to include("Eau non potable")
      expect(response.body).not_to match(/<p(?=[^>]*\bhidden)[^>]*data-non-potable-hint/)
    end

    it "efface l'origine quand le nœud cesse d'être un robinet" do
      tap = water.map_features.create!(feature_kind: "node", geometry: point,
                                       properties: { "node_type" => "tap", "water_source" => "well" })
      patch map_feature_path(tap), headers: turbo, params: { map_feature: { node_type: "valve", water_source: "well" } }
      expect(tap.reload.properties).to include("node_type" => "valve")
      expect(tap.properties).not_to have_key("water_source")
    end

    it "refuse une origine inconnue" do
      post map_features_path, headers: json, params: {
        map_feature: { map_layer_id: water.id, feature_kind: "node", geometry: point.to_json,
                       node_type: "tap", water_source: "citerne" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"].join).to include("citerne")
    end
  end
end
