require "rails_helper"

# Epic #348, phase 9 — les réseaux : eau, électricité, ethernet. Qu'un dimanche
# soir on sache où couper l'eau ou le courant.
RSpec.describe "Carte du domaine — réseaux (epic #348, phase 9)", type: :model do
  let(:point) { { "type" => "Point", "coordinates" => [4.905, 50.340] } }
  let(:line) { { "type" => "LineString", "coordinates" => [[4.905, 50.340], [4.906, 50.340]] } }

  describe "MapLayer.ensure_networks!" do
    it "crée les trois couches réseau, une seule fois, avec leur réseau et leur couleur" do
      layers = MapLayer.ensure_networks!
      expect(layers.map(&:name)).to eq(%w[Eau Électricité Ethernet])
      expect(layers.map(&:network)).to eq(%w[water electric ethernet])
      expect(layers.map(&:network_color)).to eq(%w[#2563EB #D97706 #7C3AED])
      expect(layers).to all(be_network)

      expect { MapLayer.ensure_networks! }.not_to change(MapLayer, :count)
    end

    it "adopte une couche réseau existante sans réseau déclaré plutôt que de la doubler" do
      water = MapLayer.create!(kind: "network", name: "Eau")
      expect { MapLayer.ensure_networks! }.to change(MapLayer, :count).by(2)
      expect(water.reload.network).to eq("water")
    end

    it "garde la couleur choisie à la main" do
      water = MapLayer.ensure_networks!.first
      water.update!(settings: water.settings.merge("color" => "#000000"))
      MapLayer.ensure_networks!
      expect(water.reload.network_color).to eq("#000000")
    end
  end

  describe "types de nœud" do
    it "a des clés anglaises stables et des libellés français, par réseau" do
      expect(MapLayer::NODE_TYPES["water"].values).to eq(%w[Source Captage Citerne Vanne Compteur Robinet Regard])
      expect(MapLayer::NODE_TYPES["electric"].values).to eq(%w[Tableau Compteur Prise Disjoncteur Éclairage])
      expect(MapLayer::NODE_TYPES["ethernet"].values).to eq(["Switch", "Borne wifi", "Prise murale", "Routeur", "Baie", "Boîtier fibre"])
      expect(MapLayer::NODE_TYPES.values.flat_map(&:keys)).to all(match(/\A[a-z_]+\z/))
    end

    it "accepte un type connu du réseau de la couche" do
      water = MapLayer.ensure_networks!.first
      node = water.map_features.new(feature_kind: "node", geometry: point, properties: { "node_type" => "valve" })
      expect(node).to be_valid
      expect(node.node_type_label).to eq("Vanne")
    end

    it "refuse un type d'un autre réseau" do
      water = MapLayer.ensure_networks!.first
      node = water.map_features.new(feature_kind: "node", geometry: point, properties: { "node_type" => "breaker" })
      expect(node).not_to be_valid
      expect(node.errors.full_messages.join).to include("breaker", "Eau")
    end

    it "refuse un calibre ou un équipement inconnu" do
      water = MapLayer.ensure_networks!.first
      expect(water.map_features.new(feature_kind: "line", geometry: line, properties: { "gauge" => "énorme" })).not_to be_valid
      expect(water.map_features.new(feature_kind: "node", geometry: point, properties: { "equipment" => "cisco" })).not_to be_valid
      expect(water.map_features.new(feature_kind: "node", geometry: point, properties: { "equipment" => "unifi" })).to be_valid
    end

    it "refuse un nœud qui n'est pas un point et un tracé qui n'est pas une ligne" do
      water = MapLayer.ensure_networks!.first
      expect(water.map_features.new(feature_kind: "node", geometry: line)).not_to be_valid
      expect(water.map_features.new(feature_kind: "line", geometry: point)).not_to be_valid
    end
  end

  describe "longueur d'un tracé" do
    it "se calcule en mètres (haversine) et vaut nil pour un point" do
      water = MapLayer.ensure_networks!.first
      # 0,001° de longitude à 50,34° de latitude ≈ 71 m.
      trace = water.map_features.new(feature_kind: "line", geometry: line)
      expect(trace.length_in_meters).to be_within(1).of(71)
      expect(water.map_features.new(feature_kind: "node", geometry: point).length_in_meters).to be_nil
    end
  end

  describe "#as_geojson" do
    it "porte le réseau, le type de nœud, le calibre et la couleur" do
      electric = MapLayer.ensure_networks!.second
      node = electric.map_features.create!(feature_kind: "node", geometry: point,
                                           properties: { "node_type" => "panel", "instructions" => "Levier vers le bas" })
      trace = electric.map_features.create!(feature_kind: "line", geometry: line, properties: { "gauge" => "thick" })

      expect(node.as_geojson[:properties]).to include(network: "electric", node_type: "panel", color: "#D97706")
      expect(trace.as_geojson[:properties]).to include(network: "electric", gauge: "thick")
      expect(trace.as_geojson[:properties][:length_m]).to be_within(1).of(71)
    end

    it "ne dit rien de réseau pour un objet d'une autre couche" do
      spot = MapLayer.for_kind(:management).map_features.create!(feature_kind: "point", geometry: point)
      expect(spot.as_geojson[:properties]).not_to have_key(:network)
    end
  end
end
