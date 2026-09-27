require "rails_helper"

# Epic #348, phase 8 : les plantes par l'API agent — le chemin de l'import Notion.
RSpec.describe "Api::V1 plants", type: :request do
  let(:token) { "test-token-plants" }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }

  around do |example|
    previous = ENV["AGENT_API_TOKEN"]
    ENV["AGENT_API_TOKEN"] = token
    example.run
    ENV["AGENT_API_TOKEN"] = previous
  end

  def json = JSON.parse(response.body)

  # Le corps que le script d'import enverra pour une plante complète.
  let(:notion_body) do
    {
      plant: {
        name: "Pommier Reinette Hernaut cl",
        number: 9.1,
        species_name: "Pommier",
        species_latin_name: "Malus domestica",
        variety_name: "Reinette Hernaut",
        status: "Existante",
        health: "healthy",
        production: "Moyenne",
        habit: "standard",
        stratum: "Arbre",
        stock_type: "bare_root",
        zone: "Verger",
        plant_count: 1,
        purchase_price_cents: 3500,
        planted_year: 2021,
        nursery: "Pépinière Semisto",
        notion_url: "https://www.notion.so/semisto/Pommier-9-1-abc123",
        notes: "Greffé sur M106",
        latitude: 50.3312,
        longitude: 4.8765,
        harvest_windows: [{ part: "fruit", months: [9, 10] }]
      }
    }
  end

  describe "POST /api/v1/plants" do
    it "crée une plante complète : espèce, variété, position, fenêtres" do
      post "/api/v1/plants", params: notion_body, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      data = json["data"]
      expect(data).to include("name" => "Pommier Reinette Hernaut cl", "number" => 9.1, "number_label" => "9.1",
                              "status" => "existing", "production" => "medium", "stratum" => "tree",
                              "zone" => "Verger", "notes" => "Greffé sur M106", "placed" => true,
                              "latitude" => 50.3312, "longitude" => 4.8765)
      expect(data["species"]).to include("name" => "Pommier", "latin_name" => "Malus domestica")
      expect(data["variety"]).to include("name" => "Reinette Hernaut")
      expect(data["harvest_windows_effective"]).to eq([
        { "part" => "fruit", "part_label" => "Fruit", "months" => [9, 10], "inherited" => false }
      ])
      expect(data).to include("id", "created_at", "updated_at")
      expect(json["meta"]["created"]).to be(true)

      plant = Plant.find(data["id"])
      expect(plant.map_feature.map_layer.kind).to eq("plants")
      expect(plant.plant_variety.plant_species).to eq(plant.plant_species)
    end

    it "est un upsert sur notion_url : rejouer l'import ne double rien" do
      2.times { post "/api/v1/plants", params: notion_body, headers: auth, as: :json }

      expect(response).to have_http_status(:ok)
      expect(json["meta"]["created"]).to be(false)
      expect(Plant.count).to eq(1)
      expect(MapFeature.where(feature_kind: "plant").count).to eq(1)
    end

    it "crée une plante « à placer » sans coordonnées, qui hérite des fenêtres de l'espèce" do
      species = PlantSpecies.create!(name: "Néflier")
      species.harvest_windows.create!(part: "fruit", months: [11])

      post "/api/v1/plants", params: { plant: { plant_species_id: species.id } }, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      data = json["data"]
      expect(data).to include("name" => "Néflier", "placed" => false, "latitude" => nil, "status" => "to_place")
      expect(data["harvest_windows_inherited"]).to be(true)
      expect(data["harvest_windows_effective"].first).to include("part" => "fruit", "inherited" => true)
    end

    it "refuse un numéro déjà pris, en disant par qui" do
      Plant.create!(name: "Figuier", number: 12)
      post "/api/v1/plants", params: { plant: { name: "Kaki", number: "12" } }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["messages"].join).to include("12", "Figuier")
    end

    it "refuse une valeur hors liste fermée en listant les valeurs admises" do
      post "/api/v1/plants", params: { plant: { name: "Kaki", status: "vivante", stratum: "géant" } },
                             headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      messages = json["messages"].join(" ")
      expect(messages).to include("vivante", "existing", "to_place", "géant", "shrub")
      expect(Plant.count).to eq(0)
    end

    it "refuse des coordonnées incomplètes" do
      post "/api/v1/plants", params: { plant: { name: "Kaki", latitude: 50.3 } }, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Plant.count).to eq(0)
    end

    it "refuse une variété sans espèce" do
      post "/api/v1/plants", params: { plant: { name: "Kaki", variety_name: "Fuyu" } }, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PlantVariety.count).to eq(0)
    end

    it "exige l'authentification" do
      post "/api/v1/plants", params: notion_body, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/plants/:id" do
    let!(:plant) { Plant.create!(name: "Cognassier", number: 5) }

    before { plant.place!(latitude: 50.33, longitude: 4.87) }

    it "déplace la plante" do
      patch "/api/v1/plants/#{plant.id}", params: { plant: { latitude: 50.34, longitude: 4.88 } }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("latitude" => 50.34, "longitude" => 4.88)
      expect(MapFeature.where(feature_kind: "plant").count).to eq(1)
    end

    it "la retire de la carte avec placed: false" do
      patch "/api/v1/plants/#{plant.id}", params: { plant: { placed: false } }, headers: auth, as: :json
      expect(json["data"]).to include("placed" => false, "latitude" => nil, "status" => "to_place")
    end

    it "remplace les fenêtres, et une liste vide rend l'héritage de l'espèce" do
      patch "/api/v1/plants/#{plant.id}", params: { plant: { harvest_windows: [{ part: "fruit", months: [10] }] } },
                                          headers: auth, as: :json
      expect(plant.reload.harvest_windows.map(&:months)).to eq([[10]])

      patch "/api/v1/plants/#{plant.id}", params: { plant: { harvest_windows: [] } }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(plant.reload.harvest_windows).to be_empty
    end

    it "garde son propre numéro sans se déclarer en doublon" do
      patch "/api/v1/plants/#{plant.id}", params: { plant: { number: 5, zone: "Haie" } }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(plant.reload.zone).to eq("Haie")
    end

    it "404 sur un identifiant inconnu" do
      patch "/api/v1/plants/0", params: { plant: { zone: "x" } }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/plants" do
    let!(:species) { PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica") }
    let!(:placed) { Plant.create!(name: "Pommier du verger", number: 1, zone: "Verger", status: "existing", plant_species: species) }
    let!(:loose) { Plant.create!(name: "Groseillier", number: 9.1, zone: "Potager", status: "to_confirm") }

    before { placed.place!(latitude: 50.33, longitude: 4.87) }

    it "filtre par placement, statut, zone, numéro et recherche" do
      get "/api/v1/plants", params: { placed: "true" }, headers: auth
      expect(json["data"].map { |p| p["name"] }).to eq(["Pommier du verger"])

      get "/api/v1/plants", params: { placed: "false" }, headers: auth
      expect(json["data"].map { |p| p["name"] }).to eq(["Groseillier"])

      get "/api/v1/plants", params: { status: "to_confirm" }, headers: auth
      expect(json["data"].map { |p| p["name"] }).to eq(["Groseillier"])

      get "/api/v1/plants", params: { zone: "Verger" }, headers: auth
      expect(json["data"].map { |p| p["name"] }).to eq(["Pommier du verger"])

      get "/api/v1/plants", params: { number: "9.1" }, headers: auth
      expect(json["data"].map { |p| p["number"] }).to eq([9.1])

      get "/api/v1/plants", params: { q: "malus" }, headers: auth
      expect(json["data"].map { |p| p["name"] }).to eq(["Pommier du verger"])
      expect(json["meta"]).to include("page", "per_page", "total", "pages")
    end
  end

  describe "GET/DELETE /api/v1/plants/:id" do
    let!(:plant) { Plant.create!(name: "Mûrier") }

    it "montre la fiche avec ses notes, photos et tâches" do
      MapNote.create!(subject: plant, body: "Bourgeons gelés", noted_on: Date.new(2026, 3, 12))
      get "/api/v1/plants/#{plant.id}", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"]["notes_log"].first).to include("body" => "Bourgeons gelés", "noted_on" => "2026-03-12")
      expect(json["data"]).to include("photos" => [], "tasks" => [])
    end

    it "supprime (douce) la plante" do
      delete "/api/v1/plants/#{plant.id}", headers: auth
      expect(response).to have_http_status(:no_content)
      expect(Plant.find_by(id: plant.id)).to be_nil
    end
  end
end
