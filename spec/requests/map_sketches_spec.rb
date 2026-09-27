require "rails_helper"

# Epic #348, phase 12 — les notes manuscrites : liste, création, rangement en
# dossiers, suppression, et remplacement des tracés avec verrou optimiste.
RSpec.describe "Carte du domaine — notes manuscrites (epic #348, phase 12)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:bob) { User.create!(email: "bob-dessin@les4sources.be", password: "password123") }
  let(:json_headers) { { "Accept" => "application/json" } }
  let(:stroke) { { "id" => "k3f9a2", "points" => [[50.3414, 4.9078], [50.3416, 4.9081]], "width" => 3 } }

  def json = JSON.parse(response.body)

  it "exige une session Devise" do
    get map_sketches_path, headers: json_headers
    expect(response).not_to have_http_status(:ok)
    post map_sketches_path, headers: json_headers, params: { map_sketch: { name: "Intrus" } }, as: :json
    expect(MapSketch.count).to eq(0)
  end

  context "connecté" do
    before { sign_in bob }

    it "liste les dessins rangés, sans leurs tracés" do
      MapSketch.create!(name: "Mare", folder: "Eau", strokes: [stroke])
      MapSketch.create!(name: "Libre")
      get map_sketches_path, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(json.map { |s| s["name"] }).to eq(%w[Libre Mare])
      expect(json.last).to include("folder" => "Eau", "strokes_count" => 1)
      expect(json.last).not_to have_key("strokes")
    end

    it "sert les tracés d'un dessin et sa version" do
      sketch = MapSketch.create!(name: "Mare", strokes: [stroke])
      get map_sketch_path(sketch), headers: json_headers

      expect(json["strokes"]).to eq([stroke])
      expect(json["lock_version"]).to eq(0)
    end

    it "répond 404 pour un dessin inconnu ou supprimé" do
      sketch = MapSketch.create!(name: "Parti")
      sketch.soft_delete!
      get map_sketch_path(sketch), headers: json_headers
      expect(response).to have_http_status(:not_found)
    end

    it "crée un dessin vide, signé" do
      post map_sketches_path, params: { map_sketch: { name: " Clôture nord ", folder: "Travaux" } }, as: :json

      expect(response).to have_http_status(:created)
      sketch = MapSketch.last
      expect(sketch).to have_attributes(name: "Clôture nord", folder: "Travaux", strokes: [], created_by: bob)
      expect(json).to include("id" => sketch.id, "strokes" => [])
    end

    it "refuse un dessin sans nom" do
      post map_sketches_path, params: { map_sketch: { name: " " } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].join).to include("Name")
    end

    it "renomme et déplace de dossier, sans toucher aux tracés" do
      sketch = MapSketch.create!(name: "Mare", folder: "Eau", strokes: [stroke])
      patch map_sketch_path(sketch), params: { map_sketch: { name: "Grande mare", folder: "", strokes: [] } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(sketch.reload).to have_attributes(name: "Grande mare", folder: nil, strokes: [stroke])
      expect(json["lock_version"]).to eq(sketch.lock_version)
    end

    it "supprime en douceur" do
      sketch = MapSketch.create!(name: "À jeter")
      delete map_sketch_path(sketch), as: :json

      expect(response).to have_http_status(:no_content)
      expect(MapSketch.find_by(id: sketch.id)).to be_nil
      expect(MapSketch.with_deleted { MapSketch.find(sketch.id) }).to be_present
    end

    describe "PATCH /map/sketches/:id/strokes" do
      let!(:sketch) { MapSketch.create!(name: "Mare", strokes: [stroke]) }

      it "remplace les tracés et renvoie la nouvelle version" do
        other = { "id" => "zz9", "points" => [[50.34, 4.9]], "width" => 3 }
        patch strokes_map_sketch_path(sketch), params: { strokes: [stroke, other], lock_version: 0 }, as: :json

        expect(response).to have_http_status(:ok)
        expect(sketch.reload.strokes).to eq([stroke, other])
        expect(json).to include("lock_version" => 1, "strokes_count" => 2)
        expect(json).not_to have_key("strokes")
      end

      it "accepte de tout effacer" do
        patch strokes_map_sketch_path(sketch), params: { strokes: [], lock_version: 0 }, as: :json
        expect(response).to have_http_status(:ok)
        expect(sketch.reload.strokes).to eq([])
      end

      it "répond 409 quand le dessin a changé ailleurs, sans rien écrire" do
        sketch.update!(name: "Renommé ailleurs")
        patch strokes_map_sketch_path(sketch), params: { strokes: [], lock_version: 0 }, as: :json

        expect(response).to have_http_status(:conflict)
        expect(json["lock_version"]).to eq(1)
        expect(sketch.reload.strokes).to eq([stroke])
      end

      it "exige la version lue" do
        patch strokes_map_sketch_path(sketch), params: { strokes: [] }, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(sketch.reload.strokes).to eq([stroke])
      end

      it "refuse des tracés mal formés" do
        patch strokes_map_sketch_path(sketch), params: { strokes: [{ "id" => "x", "points" => [["a", 1]], "width" => 3 }], lock_version: 0 }, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(sketch.reload.strokes).to eq([stroke])
      end
    end
  end
end
