require "rails_helper"

# Epic #348, phase 10 — le statut UniFi en direct sur la couche Ethernet :
# l'endpoint des équipements et la fiche d'un nœud UniFi. Jamais d'appel
# réseau réel : l'API Site Manager est simulée par WebMock depuis une fixture.
RSpec.describe "Carte du domaine — statut UniFi (epic #348, phase 10)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-unifi@les4sources.be", password: "password123") }
  let(:ethernet) { MapLayer.ensure_networks!.find { |layer| layer.network == "ethernet" } }
  let(:water) { MapLayer.ensure_networks!.find { |layer| layer.network == "water" } }
  let(:point) { { "type" => "Point", "coordinates" => [4.905, 50.340] } }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:devices_url) { "#{Unifi::Client::BASE_URL}#{Unifi::Client::DEVICES_PATH}" }
  let(:fixture) { file_fixture("unifi_devices.json").read }

  around do |example|
    key = ENV["UNIFI_API_KEY"]
    example.run
    ENV["UNIFI_API_KEY"] = key
  end

  before do
    ENV.delete("UNIFI_API_KEY")
    sign_in user
  end

  def with_key!
    ENV["UNIFI_API_KEY"] = "cle-de-test"
  end

  def stub_devices
    stub_request(:get, devices_url).to_return(status: 200, body: fixture,
                                              headers: { "Content-Type" => "application/json" })
  end

  def unifi_node(properties = {})
    ethernet.map_features.create!(feature_kind: "node", geometry: point, name_i18n: { "fr" => "Switch de la grange" },
                                  properties: { "node_type" => "switch", "equipment" => "unifi" }.merge(properties))
  end

  describe "GET /map/unifi/devices" do
    it "dit sans échouer que la clé n'est pas configurée" do
      get map_unifi_devices_path, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("configured" => false, "available" => false, "devices" => [])
      expect(a_request(:any, //)).not_to have_been_made
    end

    it "renvoie les équipements et leur statut" do
      with_key!
      stub_devices

      get map_unifi_devices_path, headers: { "Accept" => "application/json" }

      body = response.parsed_body
      expect(body).to include("configured" => true, "available" => true)
      expect(body["devices"].map { |d| [d["id"], d["status"]] })
        .to eq([%w[F4E2C6C23F13 online], %w[E063DA0011AA offline], %w[D021F9A0B0C1 online]])
      expect(body["devices"].first).to include("name" => "Switch grange", "model" => "USW Flex Mini",
                                               "mac" => "F4E2C6C23F13", "ip" => "192.168.1.21")
    end

    it "se dit indisponible quand l'API ne répond pas" do
      with_key!
      stub_request(:get, devices_url).to_timeout

      get map_unifi_devices_path, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("configured" => true, "available" => false, "devices" => [])
    end

    it "est réservé aux personnes connectées" do
      sign_out user

      get map_unifi_devices_path, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "la fiche d'un nœud Ethernet" do
    it "sans clé, annonce le statut indisponible sans erreur" do
      node = unifi_node("unifi_device_id" => "F4E2C6C23F13")

      get map_feature_path(node)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Statut UniFi indisponible (clé API non configurée)")
      expect(response.body).not_to include("Équipement UniFi</label>")
      expect(a_request(:any, //)).not_to have_been_made
    end

    it "avec une clé, propose les équipements et affiche celui qui est lié" do
      with_key!
      stub_devices
      node = unifi_node("unifi_device_id" => "E063DA0011AA")

      get map_feature_path(node)

      expect(response.body).to include("Équipement UniFi", "Switch grange — USW Flex Mini (F4E2C6C23F13)")
      expect(response.body).to include('data-unifi-device-status="offline"', "Hors ligne", "U6 Mesh", "192.168.1.34")
      expect(response.body).to include("Dernière remontée")
      expect(response.body).to match(/<option selected="selected" value="E063DA0011AA">/)
    end

    it "avec une clé mais une API en panne, reste lisible" do
      with_key!
      stub_request(:get, devices_url).to_return(status: 500, body: "")
      node = unifi_node("unifi_device_id" => "E063DA0011AA")

      get map_feature_path(node)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Statut UniFi indisponible (l'API UniFi ne répond pas)")
    end

    it "garde un identifiant lié que l'API ne connaît plus" do
      with_key!
      stub_devices
      node = unifi_node("unifi_device_id" => "DISPARU")

      get map_feature_path(node)

      expect(response.body).to include("Équipement introuvable (DISPARU)")
    end

    it "n'interroge pas UniFi pour un nœud sans équipement UniFi" do
      with_key!
      node = ethernet.map_features.create!(feature_kind: "node", geometry: point, properties: { "node_type" => "switch" })

      get map_feature_path(node)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Équipement UniFi")
      expect(response.body).to include("data-unifi-hint")
      expect(a_request(:any, //)).not_to have_been_made
    end

    it "ne montre rien d'UniFi sur un nœud d'un autre réseau" do
      with_key!
      node = water.map_features.create!(feature_kind: "node", geometry: point,
                                        properties: { "node_type" => "valve", "equipment" => "unifi" })

      get map_feature_path(node)

      expect(response.body).not_to include("Équipement UniFi", "data-unifi-hint")
      expect(a_request(:any, //)).not_to have_been_made
    end

    it "enregistre l'équipement UniFi choisi" do
      node = unifi_node

      patch map_feature_path(node), headers: turbo, params: { map_feature: { unifi_device_id: " F4E2C6C23F13 " } }

      expect(node.reload.properties).to include("equipment" => "unifi", "unifi_device_id" => "F4E2C6C23F13")
    end

    it "retire le lien quand on vide le choix" do
      node = unifi_node("unifi_device_id" => "F4E2C6C23F13")

      patch map_feature_path(node), headers: turbo, params: { map_feature: { unifi_device_id: "" } }

      expect(node.reload.properties).not_to have_key("unifi_device_id")
    end
  end

  it "expose le lien UniFi dans le GeoJSON de la couche Ethernet" do
    node = unifi_node("unifi_device_id" => "F4E2C6C23F13")

    get map_features_path(layer_id: ethernet.id), headers: { "Accept" => "application/json" }

    feature = response.parsed_body["features"].find { |f| f["id"] == node.id }
    expect(feature["properties"]).to include("network" => "ethernet", "equipment" => "unifi",
                                             "unifi_device_id" => "F4E2C6C23F13")
  end
end
