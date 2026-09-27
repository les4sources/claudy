require "rails_helper"

# Epic #348, phase 7 — la fiche d'une plante sur la carte : ouverte dans la
# Turbo Frame du panneau, éditée en Turbo Stream, espèce et variété créées par
# leur nom, prix en euros, photos, retrait de la carte et suppression.
RSpec.describe "Carte du domaine — plantes (epic #348, phase 7)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-plantes@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:json) { { "Accept" => "application/json" } }
  let(:apple) { PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica") }
  let(:reinette) { apple.varieties.create!(name: "Reinette Hernaut") }
  let(:plant) do
    Plant.create!(name: "Pommier Reinette Hernaut cl", number: 42, plant_species: apple, plant_variety: reinette,
                  zone: "Verger", health: "healthy", stratum: "tree")
  end
  let(:placed) { plant.place!(latitude: 50.34, longitude: 4.905) }

  it "exige une session Devise" do
    get plant_path(plant)
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    describe "la fiche" do
      it "s'ouvre dans la frame du panneau, avec l'identité et les emplacements B2" do
        get plant_path(placed)

        expect(response).to have_http_status(:ok)
        body = response.body
        expect(body).to include(%(<turbo-frame id="#{MapFeaturesController::PANEL_FRAME}"))
        expect(body).to include("Pommier Reinette Hernaut cl", "#42", "Malus domestica", "Saine", "Arbre")
        expect(body).to include(%(data-feature-panel="true"), %(data-feature-id="#{placed.map_feature_id}"))
        expect(body).to include("Retirer de la carte", "Supprimer la plante")
        expect(body).to include(%(data-controller="plant-autocomplete"))
        expect(body).to include(%(data-plant-section="harvest"), %(data-plant-section="notes"), %(data-plant-section="tasks"))
      end

      it "affiche une plante à placer sans bouton « Retirer de la carte »" do
        get plant_path(plant)
        expect(response.body).to include("À placer")
        expect(response.body).not_to include("Retirer de la carte")
      end

      it "n'ouvre pas une plante supprimée" do
        plant.soft_delete!(validate: false)
        expect { get plant_path(plant) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe "l'enregistrement de l'identité" do
      before { plant }

      it "met à jour la fiche et répond par un Turbo Stream qui la remplace" do
        patch plant_path(placed), headers: turbo, params: {
          plant: { name: "Le grand pommier", number: "#7", zone: "Haut du verger", status: "existing",
                   health: "worrying", production: "high", habit: "standard", stratum: "tree",
                   plant_count: "2", nursery: "Pépinière Bauwens", planted_on: "2021-11-20",
                   altitude: "185", notion_url: "https://www.notion.so/abc", notes: " Taille en février. " }
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("turbo-stream", MapFeaturesController::PANEL_FRAME, "Enregistré.",
                                         %(data-feature-saved="true"))
        placed.reload
        expect(placed).to have_attributes(name: "Le grand pommier", zone: "Haut du verger", health: "worrying",
                                          production: "high", plant_count: 2, nursery: "Pépinière Bauwens",
                                          planted_on: Date.new(2021, 11, 20), planted_year: 2021, altitude: 185)
        expect(placed.number_label).to eq("7")
        expect(placed.notes).to eq("Taille en février.")
        # Le point sur la carte porte le nouveau nom.
        expect(placed.map_feature.reload.name).to eq("Le grand pommier")
      end

      it "accepte un numéro décimal à la virgule" do
        patch plant_path(plant), headers: turbo, params: { plant: { number: "9,1" } }
        expect(plant.reload.number_label).to eq("9.1")
      end

      it "convertit le prix d'achat en euros vers des cents" do
        patch plant_path(plant), headers: turbo, params: { plant: { purchase_price: "24,50" } }
        expect(plant.reload.purchase_price_cents).to eq(2450)

        patch plant_path(plant), headers: turbo, params: { plant: { purchase_price: "" } }
        expect(plant.reload.purchase_price_cents).to be_nil
      end

      it "refuse un prix illisible en 422, sans rien enregistrer" do
        patch plant_path(plant), headers: turbo, params: { plant: { name: "Renommé", purchase_price: "douze" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Prix d&#39;achat illisible")
        expect(plant.reload.name).to eq("Pommier Reinette Hernaut cl")
      end

      it "crée l'espèce et la variété par leur nom, sans égard à la casse" do
        expect {
          patch plant_path(plant), headers: turbo, params: { plant: { species_name: "néflier", variety_name: "Nottingham" } }
        }.to change(PlantSpecies, :count).by(1).and change(PlantVariety, :count).by(1)

        plant.reload
        expect(plant.plant_species.name).to eq("néflier")
        expect(plant.plant_species.created_by).to eq(user)
        expect(plant.plant_variety.name).to eq("Nottingham")

        expect {
          patch plant_path(plant), headers: turbo, params: { plant: { species_name: "POMMIER", variety_name: "reinette hernaut" } }
        }.not_to change(PlantSpecies, :count)
        expect(plant.reload.plant_species).to eq(apple)
        expect(plant.plant_variety).to eq(reinette)
      end

      it "retire espèce et variété quand l'espèce est vidée" do
        patch plant_path(plant), headers: turbo, params: { plant: { species_name: "", variety_name: "" } }
        plant.reload
        expect(plant.plant_species).to be_nil
        expect(plant.plant_variety).to be_nil
      end

      it "refuse une variété sans espèce, et n'en crée aucune" do
        expect {
          patch plant_path(plant), headers: turbo, params: { plant: { species_name: "", variety_name: "Orpheline" } }
        }.not_to change(PlantVariety, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("indiquez d&#39;abord l&#39;espèce")
      end

      it "rend les erreurs du modèle lisibles en 422, et annule l'espèce créée" do
        Plant.create!(name: "Autre", number: 8)
        expect {
          patch plant_path(plant), headers: turbo, params: { plant: { number: "8", species_name: "Cognassier" } }
        }.not_to change(PlantSpecies, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("est déjà pris par une autre plante")
        # Le nom tapé revient dans le champ, pour ne pas le retaper.
        expect(response.body).to include(%(value="Cognassier"))
        expect(plant.reload.number_label).to eq("42")
      end
    end

    describe "les photos" do
      let(:png) do
        fixture_file_upload(Rails.root.join("spec/fixtures/files/map-tiles/test-layer/rgb/12/2103/1383.png"), "image/png")
      end

      it "en ajoute plusieurs et en retire une" do
        patch plant_path(plant), headers: turbo, params: { plant: { photos: [png, png] } }
        expect(plant.reload.photos.count).to eq(2)
        expect(response.body).to include("Photos (2)")

        delete photo_plant_path(plant, photo_id: plant.photos.first.id), headers: turbo
        expect(response).to have_http_status(:ok)
        expect(plant.reload.photos.count).to eq(1)
      end

      it "refuse une pièce jointe qui n'est pas une photo" do
        pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", original_filename: "plan.pdf")
        patch plant_path(plant), headers: turbo, params: { plant: { photos: [pdf] } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("plan.pdf")
      end
    end

    it "retire la plante de la carte : le point disparaît, la fiche reste ouverte" do
      feature = placed.map_feature
      post unplace_plant_path(placed), headers: turbo

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-layer-reload="#{feature.map_layer_id}"), "À placer")
      expect(placed.reload.map_feature_id).to be_nil
      expect(placed.status).to eq("to_place")
      expect(MapFeature.find_by(id: feature.id)).to be_nil
    end

    it "supprime la plante (soft-delete) avec son point" do
      feature = placed.map_feature
      delete plant_path(placed), headers: turbo

      expect(response.body).to include(%(data-feature-deleted="#{feature.id}"), %(data-layer-id="#{feature.map_layer_id}"))
      expect(Plant.find_by(id: placed.id)).to be_nil
      expect(Plant.unscoped.find(placed.id).deleted_at).to be_present
      expect(MapFeature.find_by(id: feature.id)).to be_nil
    end

    describe "l'autocomplétion" do
      before do
        apple
        PlantSpecies.create!(name: "Néflier", latin_name: "Mespilus germanica")
        PlantSpecies.create!(name: "Poirier", latin_name: "Pyrus communis")
      end

      it "cherche les espèces par nom ou nom latin" do
        get map_species_path(format: :json, q: "mespil"), headers: json
        expect(JSON.parse(response.body)).to eq([{ "id" => PlantSpecies.named("Néflier").first.id, "name" => "Néflier",
                                                   "latin_name" => "Mespilus germanica",
                                                   "label" => "Néflier (Mespilus germanica)" }])

        get map_species_path(format: :json), headers: json
        expect(JSON.parse(response.body).map { |s| s["name"] }).to eq(%w[Néflier Poirier Pommier])
      end

      it "limite à dix résultats" do
        12.times { |i| PlantSpecies.create!(name: "Prunier #{i}") }
        get map_species_path(format: :json, q: "prunier"), headers: json
        expect(JSON.parse(response.body).size).to eq(10)
      end

      it "cherche les variétés d'une espèce" do
        reinette
        apple.varieties.create!(name: "Boskoop")
        get map_species_varieties_path(apple, format: :json, q: "rein"), headers: json
        expect(JSON.parse(response.body)).to eq([{ "id" => reinette.id, "name" => "Reinette Hernaut" }])

        get map_species_varieties_path(apple, format: :json), headers: json
        expect(JSON.parse(response.body).map { |v| v["name"] }).to eq(["Boskoop", "Reinette Hernaut"])
      end
    end

    describe "la couche Plantes" do
      it "existe dès l'ouverture de la carte" do
        get map_path
        expect(MapLayer.where(kind: "plants").count).to eq(1)
      end

      it "expose la plante dans le GeoJSON des objets" do
        placed.update!(health: "sick")
        get map_features_path(format: :json, layer_id: placed.map_feature.map_layer_id), headers: json

        feature = JSON.parse(response.body)["features"].first
        expect(feature["properties"]).to include("feature_kind" => "plant", "name" => "Pommier Reinette Hernaut cl",
                                                 "plant_id" => placed.id, "health" => "sick", "stratum" => "tree",
                                                 "status" => "existing", "dead" => false, "number" => "42")
      end
    end
  end
end
