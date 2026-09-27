require "rails_helper"

# Epic #348, phase 8 : espèces et variétés par l'API agent.
RSpec.describe "Api::V1 plant species & varieties", type: :request do
  let(:token) { "test-token-plants" }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }

  around do |example|
    previous = ENV["AGENT_API_TOKEN"]
    ENV["AGENT_API_TOKEN"] = token
    example.run
    ENV["AGENT_API_TOKEN"] = previous
  end

  def json = JSON.parse(response.body)

  describe "POST /api/v1/plant_species" do
    let(:body) do
      { plant_species: { name: "Pommier", latin_name: "Malus domestica", family: "Rosaceae",
                         exposure: ["Soleil", "Mi-ombre"], edible_parts: ["Fruit"],
                         harvest_windows: [{ part: "fruit", months: [9, 10] }, { part: "Fleur", months: [4] }] } }
    end

    it "crée l'espèce avec sa fiche botanique et ses fenêtres par défaut" do
      post "/api/v1/plant_species", params: body, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      data = json["data"]
      expect(data).to include("name" => "Pommier", "latin_name" => "Malus domestica", "family" => "Rosaceae",
                              "exposure" => ["Soleil", "Mi-ombre"], "edible_parts" => ["Fruit"])
      expect(data["harvest_windows"]).to contain_exactly(
        include("part" => "flower", "months" => [4]), include("part" => "fruit", "months" => [9, 10])
      )
      expect(data).to include("id", "created_at", "updated_at")
      expect(json["meta"]["created"]).to be(true)
    end

    it "est un upsert sur le nom, casse ignorée" do
      species = PlantSpecies.create!(name: "Pommier")
      post "/api/v1/plant_species", params: { plant_species: { name: "pommier", family: "Rosaceae" } },
                                    headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["data"]["id"]).to eq(species.id)
      expect(json["meta"]["created"]).to be(false)
      expect(PlantSpecies.count).to eq(1)
    end

    it "refuse une partie inconnue en listant les valeurs admises" do
      post "/api/v1/plant_species",
           params: { plant_species: { name: "Pommier", harvest_windows: [{ part: "écorce", months: [1] }] } },
           headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["messages"].join).to include("écorce", "fruit", "flower")
      expect(PlantSpecies.count).to eq(0)
    end

    it "exige l'authentification" do
      post "/api/v1/plant_species", params: body, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/plant_species/:id" do
    let!(:species) { PlantSpecies.create!(name: "Néflier") }

    before { species.harvest_windows.create!(part: "fruit", months: [11]) }

    it "met à jour la fiche et remplace les fenêtres" do
      patch "/api/v1/plant_species/#{species.id}",
            params: { plant_species: { latin_name: "Mespilus germanica", harvest_windows: [{ part: "leaf", months: [5] }] } },
            headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(species.reload.latin_name).to eq("Mespilus germanica")
      expect(species.harvest_windows.map(&:part)).to eq(["leaf"])
    end

    it "garde les fenêtres quand harvest_windows est absent" do
      patch "/api/v1/plant_species/#{species.id}", params: { plant_species: { notes: "Blettir" } },
                                                   headers: auth, as: :json
      expect(species.reload.harvest_windows.map(&:part)).to eq(["fruit"])
    end
  end

  describe "GET /api/v1/plant_species" do
    it "liste et cherche par nom latin" do
      PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica")
      PlantSpecies.create!(name: "Poirier", latin_name: "Pyrus communis")

      get "/api/v1/plant_species", params: { q: "malus" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |s| s["name"] }).to eq(["Pommier"])
      expect(json["meta"]).to include("page", "total")
    end
  end

  describe "variétés" do
    let!(:pommier) { PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica") }
    let!(:poirier) { PlantSpecies.create!(name: "Poirier") }

    it "crée une variété (upsert sur espèce + nom)" do
      post "/api/v1/plant_varieties", params: { plant_variety: { plant_species_id: pommier.id, name: "Reinette Hernaut" } },
                                      headers: auth, as: :json
      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("name" => "Reinette Hernaut", "plant_species_id" => pommier.id)
      expect(json["data"]["species"]).to include("name" => "Pommier", "latin_name" => "Malus domestica")

      post "/api/v1/plant_varieties", params: { plant_variety: { species_name: "pommier", name: "reinette hernaut" } },
                                      headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(json["meta"]["created"]).to be(false)
      expect(PlantVariety.count).to eq(1)
    end

    it "refuse une variété sans espèce" do
      post "/api/v1/plant_varieties", params: { plant_variety: { name: "Orpheline" } }, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "filtre par plant_species_id" do
      pommier.find_or_create_variety!("Boskoop")
      poirier.find_or_create_variety!("Conférence")

      get "/api/v1/plant_varieties", params: { plant_species_id: poirier.id }, headers: auth
      expect(json["data"].map { |v| v["name"] }).to eq(["Conférence"])
    end
  end
end
