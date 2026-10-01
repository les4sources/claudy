require "rails_helper"

# Les aménagements à l'essai de la vue 3D du relief : baissières, keylines et
# mares, enregistrés comme objets de la couche « Aménagements à l'essai ».
RSpec.describe "Carte du domaine — aménagements à l'essai", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-design@les4sources.be", password: "password123") }
  let(:line) { { type: "LineString", coordinates: [[4.9070, 50.3410], [4.9075, 50.3411], [4.9080, 50.3411]] } }
  let(:circle) do
    ring = (0..8).map { |k| [4.9078 + 0.0001 * Math.cos(k * Math::PI / 4), 50.3414 + 0.00006 * Math.sin(k * Math::PI / 4)] }
    ring[-1] = ring[0]
    { type: "Polygon", coordinates: [ring] }
  end

  def post_design(**attrs)
    post map_designs_path, params: { design: attrs }, as: :json
  end

  it "exige une session" do
    get map_designs_path, as: :json

    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    it "enregistre une keyline avec ses cotes, dans la couche dédiée" do
      post_design(type: "keyline", geometry: line.to_json, width: 2, depth: 0.5, berm: 0.4, grade: 1)

      expect(response).to have_http_status(:created)
      feature = MapFeature.last
      expect(feature.map_layer.kind).to eq("design")
      expect(feature.map_layer.name).to eq("Aménagements à l'essai")
      expect(feature.feature_kind).to eq("path")
      expect(feature.design).to eq("type" => "keyline", "width" => 2.0, "depth" => 0.5, "berm" => 0.4, "grade" => 1.0)
      expect(JSON.parse(response.body).dig("properties", "design", "type")).to eq("keyline")
      expect(feature.created_by).to eq(user)
    end

    it "numérote les mares et garde leur centre" do
      2.times { post_design(type: "pond", geometry: circle.to_json, radius: 5, depth: 1.5, berm: 0.3, center: [4.9078, 50.3414]) }

      ponds = MapFeature.where(map_layer: MapLayer.for_kind(:design)).order(:id)
      expect(ponds.map(&:display_name)).to eq(["Mare 1", "Mare 2"])
      expect(ponds.last.feature_kind).to eq("zone")
      expect(ponds.last.design["center"]).to eq([4.9078, 50.3414])
    end

    it "refuse un type inconnu, une cote absurde ou une géométrie qui ne va pas" do
      post_design(type: "lac", geometry: line.to_json)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"].join).to include("lac")

      post_design(type: "pond", geometry: circle.to_json, radius: 5, depth: 300)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"].join).to include("depth")

      post_design(type: "pond", geometry: line.to_json, radius: 5, depth: 1)
      expect(response).to have_http_status(:unprocessable_content)
      expect(MapFeature.count).to eq(0)
    end

    it "liste puis retire (soft-delete) un aménagement" do
      post_design(type: "swale", geometry: line.to_json, width: 2, depth: 0.5, berm: 0.4, grade: 0)
      id = JSON.parse(response.body)["id"]

      get map_designs_path, as: :json
      expect(JSON.parse(response.body)["features"].map { |f| f["id"] }).to eq([id])

      delete map_design_path(id), as: :json
      expect(response).to have_http_status(:no_content)
      get map_designs_path, as: :json
      expect(JSON.parse(response.body)["features"]).to be_empty
      expect(MapFeature.unscoped.find(id).deleted_at).to be_present
    end

    it "ne retire que les aménagements, pas un objet d'une autre couche" do
      other = MapLayer.for_kind(:management).map_features.create!(geometry: line.deep_stringify_keys, feature_kind: "path")

      expect { delete map_design_path(other.id), as: :json }.to raise_error(ActiveRecord::RecordNotFound)
      expect(other.reload.deleted_at).to be_nil
    end

    it "passe l'adresse des aménagements à la vue 3D" do
      root = Pathname(Dir.mktmpdir("map-terrain"))
      terrain = Maps::Terrain.new(root: root)
      allow(Maps::Terrain).to receive(:current).and_return(terrain)
      FileUtils.mkdir_p(root)
      File.binwrite(terrain.grid_path, [0, 0, 0, 0].pack("v*"))
      File.write(terrain.metadata_path, { cols: 2, rows: 2, z_min: 100, z_unit: 0.01 }.to_json)

      get map_relief_path

      scene = Nokogiri::HTML(response.body).at_css('[data-controller="map-relief"]')
      expect(scene["data-map-relief-designs-url-value"]).to eq("/map/relief/designs")
      expect(response.body).to include("Aménagements à l'essai")
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
