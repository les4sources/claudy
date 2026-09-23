require "rails_helper"

# Epic #348, phase 2 — couches et objets : la carte lit et écrit les géométries
# en JSON, la fiche latérale édite le reste en Turbo Stream.
RSpec.describe "Carte du domaine — objets (epic #348, phase 2)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-objets@les4sources.be", password: "password123") }
  let(:layer) { MapLayer.for_kind(:management) }
  let(:polygon) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:json) { { "Accept" => "application/json" } }

  def zone(**attrs)
    layer.map_features.create!({ feature_kind: "zone", geometry: polygon, name_i18n: { "fr" => "Le potager" } }.merge(attrs))
  end

  it "exige une session Devise" do
    get map_features_path(format: :json, layer_id: layer.id)
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    it "la page carte liste la couche Gestion et sa barre d'outils" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      get map_path
      expect(response).to have_http_status(:ok)
      expect(MapLayer.where(kind: "management").count).to eq(1)
      expect(response.body).to include("Gestion", "Outils de la couche Gestion", "feature_panel")
    end

    it "renvoie une FeatureCollection GeoJSON filtrée par couche" do
      mine = zone(properties: { "management_notes" => "Fauche en juin" })
      other = MapLayer.create!(kind: "network", name: "Eau")
      other.map_features.create!(feature_kind: "node", geometry: { "type" => "Point", "coordinates" => [4.9, 50.34] })

      get map_features_path(format: :json, layer_id: layer.id)

      body = JSON.parse(response.body)
      expect(body["type"]).to eq("FeatureCollection")
      expect(body["features"].size).to eq(1)
      feature = body["features"].first
      expect(feature["id"]).to eq(mine.id)
      expect(feature["geometry"]).to eq(polygon)
      expect(feature["properties"]).to include("feature_kind" => "zone", "name" => "Le potager", "photos_count" => 0)
    end

    it "sert la fiche d'un nouvel objet sans rien créer" do
      expect {
        get new_map_feature_path(layer_id: layer.id, feature_kind: "zone")
      }.not_to change(MapFeature, :count)
      expect(response.body).to include("Nouvel objet", "Consigne de gestion", "feature_panel")
    end

    it "crée un objet depuis la fiche, en Turbo Stream" do
      expect {
        post map_features_path, headers: turbo, params: {
          map_feature: { map_layer_id: layer.id, feature_kind: "zone", geometry: polygon.to_json,
                         name: "Le potager", description: "Derrière la grange", management_notes: "Désherbage régulier." }
        }
      }.to change(MapFeature, :count).by(1)

      feature = MapFeature.last
      expect(feature.name).to eq("Le potager")
      expect(feature.description_i18n).to eq("fr" => "Derrière la grange")
      expect(feature.management_notes).to eq("Désherbage régulier.")
      expect(feature.created_by).to eq(user)
      expect(response.body).to include("turbo-stream", "feature_panel", "Enregistré.", %(data-feature-saved="true"))
    end

    it "déduit le type d'objet de la géométrie quand il manque" do
      post map_features_path, headers: json, params: {
        map_feature: { map_layer_id: layer.id, geometry: { "type" => "LineString", "coordinates" => [[4.9, 50.34], [4.91, 50.341]] }.to_json }
      }
      expect(response).to have_http_status(:created)
      expect(MapFeature.last.feature_kind).to eq("path")
    end

    it "refuse une géométrie invalide avec la fiche et ses erreurs" do
      expect {
        post map_features_path, headers: turbo, params: {
          map_feature: { map_layer_id: layer.id, feature_kind: "zone", geometry: "", name: "Rien" }
        }
      }.not_to change(MapFeature, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Point, une LineString ou un Polygon")
    end

    it "met à jour la géométrie en JSON (sommets déplacés)" do
      feature = zone
      moved = { "type" => "Polygon",
                "coordinates" => [[[4.907, 50.340], [4.908, 50.340], [4.908, 50.341], [4.907, 50.340]]] }

      patch map_feature_path(feature, format: :json), params: { map_feature: { geometry: moved.to_json } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(feature.reload.geometry).to eq(moved)
      expect(feature.name).to eq("Le potager")
    end

    it "garde les autres langues quand on édite le français" do
      feature = zone(name_i18n: { "fr" => "Le potager", "nl" => "De moestuin" })
      patch map_feature_path(feature), headers: turbo, params: { map_feature: { name: "Le grand potager" } }
      expect(feature.reload.name_i18n).to eq("fr" => "Le grand potager", "nl" => "De moestuin")
    end

    it "ajoute des photos et en retire une" do
      feature = zone
      photo = fixture_file_upload(Rails.root.join("spec/fixtures/files/map-tiles/test-layer/rgb/12/2103/1383.png"), "image/png")

      patch map_feature_path(feature), headers: turbo, params: { map_feature: { photos: [photo] } }
      expect(feature.reload.photos.count).to eq(1)

      delete photo_map_feature_path(feature, photo_id: feature.photos.first.id), headers: turbo
      expect(response.body).to include("feature_panel")
      expect(feature.reload.photos.count).to eq(0)
    end

    it "refuse une pièce jointe qui n'est pas une photo" do
      feature = zone
      pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", original_filename: "plan.pdf")
      patch map_feature_path(feature), headers: turbo, params: { map_feature: { photos: [pdf] } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("plan.pdf")
    end

    it "supprime par soft-delete" do
      feature = zone
      delete map_feature_path(feature, format: :json)

      expect(response).to have_http_status(:no_content)
      expect(MapFeature.where(id: feature.id)).to be_empty
      expect(MapFeature.unscoped.find(feature.id).deleted_at).to be_present
    end

    it "supprimer depuis la fiche renvoie le marqueur qui retire l'objet de la carte" do
      feature = zone
      delete map_feature_path(feature), headers: turbo

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-feature-deleted="#{feature.id}"), %(data-layer-id="#{layer.id}"))
      expect(MapFeature.where(id: feature.id)).to be_empty
    end

    it "la fiche d'un objet existant n'envoie pas sa géométrie (seul le déplacement des sommets l'écrit)" do
      feature = zone
      get map_feature_path(feature)
      expect(response.body).not_to include("feature-geometry")

      get new_map_feature_path(layer_id: layer.id, feature_kind: "zone")
      expect(response.body).to include("feature-geometry")
    end
  end
end
