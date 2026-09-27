require "rails_helper"

# Epic #348, phase 8 : notes datées, photos, tâches et objets de la carte par
# l'API agent.
RSpec.describe "Api::V1 carte (notes, photos, tâches, objets)", type: :request do
  let(:token) { "test-token-map" }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }
  let(:plant) { Plant.create!(name: "Pommier 1", number: 1) }
  let(:layer) { MapLayer.for_kind(:management) }
  let(:polygon) do
    { type: "Polygon", coordinates: [[[4.87, 50.33], [4.88, 50.33], [4.88, 50.34], [4.87, 50.33]]] }
  end

  around do |example|
    previous = ENV["AGENT_API_TOKEN"]
    ENV["AGENT_API_TOKEN"] = token
    example.run
    ENV["AGENT_API_TOKEN"] = previous
  end

  def json = JSON.parse(response.body)

  def png = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/capture.png"), "image/png")

  describe "notes datées" do
    it "ajoute une note à une plante, la modifie puis la supprime" do
      post "/api/v1/plants/#{plant.id}/notes", params: { map_note: { body: "Bourgeons gelés", noted_on: "2026-03-12" } },
                                               headers: auth, as: :json
      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("body" => "Bourgeons gelés", "noted_on" => "2026-03-12",
                                      "subject_type" => "Plant", "subject_id" => plant.id)
      note_id = json["data"]["id"]

      patch "/api/v1/map_notes/#{note_id}", params: { map_note: { body: "Bourgeons gelés, 3 branches" } },
                                            headers: auth, as: :json
      expect(json["data"]["body"]).to eq("Bourgeons gelés, 3 branches")

      delete "/api/v1/map_notes/#{note_id}", headers: auth
      expect(response).to have_http_status(:no_content)
      expect(plant.map_notes.reload).to be_empty
    end

    it "refuse une note vide" do
      post "/api/v1/plants/#{plant.id}/notes", params: { map_note: { body: " " } }, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "404 sur une plante inconnue" do
      post "/api/v1/plants/0/notes", params: { map_note: { body: "x" } }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "photos" do
    it "attache plusieurs photos à une plante et renvoie leurs identifiants" do
      post "/api/v1/plants/#{plant.id}/photos", params: { photos: [png, png] }, headers: auth

      expect(response).to have_http_status(:created)
      expect(json["photos"].size).to eq(2)
      expect(json["photos"].first).to include("id", "filename" => "capture.png", "content_type" => "image/png")
      expect(json["photos"].first["url"]).to include("/rails/active_storage/")
      expect(plant.photos.count).to eq(2)

      delete "/api/v1/plants/#{plant.id}/photos/#{json['photos'].first['id']}", headers: auth
      expect(response).to have_http_status(:no_content)
      expect(plant.photos.reload.count).to eq(1)
    end

    it "refuse un fichier qui n'est pas une photo, sans rien attacher" do
      text = Rack::Test::UploadedFile.new(StringIO.new("pas une image"), "text/plain", original_filename: "notes.txt")
      post "/api/v1/plants/#{plant.id}/photos", params: { photos: [text] }, headers: auth

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["messages"].join).to include("notes.txt")
      expect(plant.photos.reload.count).to eq(0)
    end

    it "refuse un envoi sans fichier" do
      post "/api/v1/plants/#{plant.id}/photos", params: {}, headers: auth
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "attache une photo à un objet de la carte" do
      feature = MapFeature.create!(map_layer: layer, feature_kind: "zone", geometry: polygon.deep_stringify_keys)
      post "/api/v1/map_features/#{feature.id}/photos", params: { photos: [png] }, headers: auth
      expect(response).to have_http_status(:created)
      expect(feature.photos.count).to eq(1)
    end
  end

  describe "tâches" do
    it "crée, liste, modifie et supprime une tâche sur une plante" do
      post "/api/v1/map_tasks", params: { map_task: { subject_type: "Plant", subject_id: plant.id,
                                                      label: "Taille d'hiver", months: [2] } },
                                headers: auth, as: :json
      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("label" => "Taille d'hiver", "months" => [2], "sector" => "nourricier")
      task_id = json["data"]["id"]

      get "/api/v1/map_tasks", params: { subject_type: "Plant", subject_id: plant.id }, headers: auth
      expect(json["data"].map { |t| t["id"] }).to eq([task_id])

      patch "/api/v1/map_tasks/#{task_id}", params: { map_task: { months: [2, 3], sector: "Terrain" } },
                                            headers: auth, as: :json
      expect(json["data"]).to include("months" => [2, 3], "sector" => "terrain")

      delete "/api/v1/map_tasks/#{task_id}", headers: auth
      expect(response).to have_http_status(:no_content)
      expect(MapTask.count).to eq(0)
    end

    it "refuse un type de porteur hors liste" do
      post "/api/v1/map_tasks", params: { map_task: { subject_type: "User", subject_id: 1, label: "x" } },
                                headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["messages"].join).to include("MapFeature", "Plant")
    end

    it "refuse un porteur introuvable" do
      post "/api/v1/map_tasks", params: { map_task: { subject_type: "Plant", subject_id: 0, label: "x" } },
                                headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "objets de la carte" do
    it "crée une zone par layer_kind, la modifie, la liste et la supprime" do
      post "/api/v1/map_features",
           params: { map_feature: { layer_kind: "management", geometry: polygon, name_i18n: { fr: "Prairie du bas", xx: "?" },
                                    properties: { management_notes: "Fauche tardive" } } },
           headers: auth, as: :json
      expect(response).to have_http_status(:created)
      data = json["data"]
      expect(data).to include("feature_kind" => "zone", "layer_kind" => "management", "name" => "Prairie du bas",
                              "name_i18n" => { "fr" => "Prairie du bas" }, "geometry_type" => "Polygon")
      expect(data["properties"]).to eq("management_notes" => "Fauche tardive")
      id = data["id"]

      patch "/api/v1/map_features/#{id}", params: { map_feature: { description_i18n: { fr: "Humide" } } },
                                          headers: auth, as: :json
      expect(json["data"]["description_i18n"]).to eq("fr" => "Humide")

      get "/api/v1/map_features", params: { layer_id: layer.id, kind: "zone" }, headers: auth
      expect(json["data"].map { |f| f["id"] }).to eq([id])

      delete "/api/v1/map_features/#{id}", headers: auth
      expect(response).to have_http_status(:no_content)
      expect(MapFeature.find_by(id: id)).to be_nil
    end

    it "refuse une géométrie invalide et une couche absente" do
      post "/api/v1/map_features", params: { map_feature: { layer_id: layer.id, geometry: { type: "Point", coordinates: [500, 50] } } },
                                   headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "/api/v1/map_features", params: { map_feature: { geometry: polygon } }, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["messages"].join).to include("layer_id")
    end

    it "renvoie vers /plants pour poser un point de plante" do
      post "/api/v1/map_features", params: { map_feature: { layer_kind: "plants", feature_kind: "plant",
                                                            geometry: { type: "Point", coordinates: [4.87, 50.33] } } },
                                   headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["messages"].join).to include("/plants")
    end
  end

  it "n'expose aucune écriture dans l'API publique" do
    public_routes = Rails.application.routes.routes.select { |route| route.path.spec.to_s.start_with?("/api/public") }
    expect(public_routes.map(&:verb).uniq).to eq(["GET"])
  end
end
