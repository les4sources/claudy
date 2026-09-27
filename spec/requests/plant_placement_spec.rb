require "rails_helper"

# Epic #348, phase 7 — le mode Placement : la liste des plantes à placer
# (`GET /map/plants/unplaced`, filtres zone et recherche) et la pose ou le
# déplacement d'un point (`POST /map/plants/:id/place`).
RSpec.describe "Carte du domaine — placer les plantes (epic #348, phase 7)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-placement@les4sources.be", password: "password123") }
  let(:json) { { "Accept" => "application/json" } }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:apple) { PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica") }
  let(:pear) { PlantSpecies.create!(name: "Poirier") }
  let!(:reinette) { Plant.create!(name: "Pommier Reinette Hernaut", number: 3, plant_species: apple, zone: "Verger", status: "to_place") }
  let!(:conference) { Plant.create!(name: "Poirier Conférence", number: 1, plant_species: pear, zone: "Verger", status: "to_place") }
  let!(:medlar) { Plant.create!(name: "Néflier", number: 2, zone: "Potager", status: "to_place") }

  it "exige une session Devise" do
    get unplaced_plants_path
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    describe "la liste des plantes à placer" do
      it "rend la frame du tiroir, triée par numéro, sans les plantes placées ni mortes" do
        Plant.create!(name: "Pommier mort", status: "dead")
        Plant.create!(name: "Cognassier placé").place!(latitude: 50.34, longitude: 4.905)

        get unplaced_plants_path

        expect(response).to have_http_status(:ok)
        body = response.body
        expect(body).to include(%(<turbo-frame id="#{PlantsController::UNPLACED_FRAME}"), %(data-unplaced-total="3"))
        expect(body.index("Poirier Conférence")).to be < body.index("Néflier")
        expect(body.index("Néflier")).to be < body.index("Pommier Reinette Hernaut")
        expect(body).to include("#1", "map#pickPlant")
        expect(body).not_to include("Pommier mort", "Cognassier placé")
        expect(body).to include(%(<option value="Potager">), %(<option value="Verger">))
      end

      it "filtre par zone" do
        get unplaced_plants_path(zone: "Potager")
        expect(response.body).to include("Néflier", "1 sur 3 à placer")
        expect(response.body).not_to include("Poirier Conférence")
      end

      it "filtre par recherche (nom d'espèce ou numéro)" do
        get unplaced_plants_path(q: "pommier")
        expect(response.body).to include("Pommier Reinette Hernaut")
        expect(response.body).not_to include("Néflier")

        get unplaced_plants_path(q: "#2")
        expect(response.body).to include("Néflier")
        expect(response.body).not_to include("Pommier Reinette Hernaut")
      end

      it "marque la plante en cours de placement" do
        get unplaced_plants_path(selected: medlar.id)
        expect(response.body).to match(/aria-pressed="true"[^>]*data-plant-id="#{medlar.id}"/)
      end

      it "félicite quand tout est placé" do
        Plant.to_place.find_each { |plant| plant.place!(latitude: 50.34, longitude: 4.905) }
        get unplaced_plants_path
        expect(response.body).to include("Toutes les plantes sont sur la carte.")
      end
    end

    describe "la carte" do
      before do
        MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                             bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      end

      it "montre le compteur « À placer », le tiroir et le bandeau du mode Placement" do
        get map_path(plant: medlar.id)

        body = response.body
        expect(body).to include(%(data-map-placement-link="true"), %(data-action="map#openPlacement"))
        expect(body).to include(%(data-map-target="unplacedCount"), %(data-map-target="placementDrawer"), %(data-placement-banner="true"))
        expect(body).to match(%r{data-map-target="unplacedCount">\s*3\s*<})
        expect(body).to include(%(data-map-focus-plant-value="#{medlar.id}"), %(data-map-place-url-value="/map/plants/__ID__/place"))
      end

      it "ignore une plante inconnue dans l'URL" do
        get map_path(plant: "999999")
        expect(response.body).not_to include("data-map-focus-plant-value=")
      end

      it "propose « Placer sur la carte » et « Je suis devant » dans la fiche d'une plante à placer" do
        get plant_path(medlar)
        expect(response.body).to include("Placer sur la carte", "Je suis devant", %(data-action="map#placePlantFromPanel"))
      end

      it "propose « Déplacer » et « Placer ici (GPS) » dans la fiche d'une plante placée" do
        reinette.place!(latitude: 50.34, longitude: 4.905)
        get plant_path(reinette)
        expect(response.body).to include("Déplacer", "Placer ici (GPS)", %(data-action="map#movePlant"),
                                         %(data-feature-id="#{reinette.map_feature_id}"))
      end
    end

    describe "la pose d'un point" do
      it "crée le point dans la couche Plantes et passe la plante « à placer » à « existante »" do
        expect do
          post place_plant_path(reinette), headers: json, params: { latitude: "50,3412", longitude: "4.9051" }
        end.to change(MapFeature, :count).by(1)

        expect(response).to have_http_status(:ok)
        reinette.reload
        feature = reinette.map_feature
        expect(feature).to have_attributes(feature_kind: "plant", map_layer: MapLayer.for_kind(:plants), name: "Pommier Reinette Hernaut")
        expect(feature.geometry).to eq("type" => "Point", "coordinates" => [4.9051, 50.3412])
        expect(feature.created_by).to eq(user)
        expect(reinette.status).to eq("existing")

        data = JSON.parse(response.body)
        expect(data).to include("plant_id" => reinette.id, "map_feature_id" => feature.id, "layer_id" => feature.map_layer_id,
                                "moved" => false, "remaining" => 2, "latitude" => 50.3412, "longitude" => 4.9051)
      end

      it "déplace le point d'une plante déjà placée, sans en créer un second" do
        reinette.place!(latitude: 50.34, longitude: 4.905)
        feature_id = reinette.map_feature_id

        expect do
          post place_plant_path(reinette), headers: json, params: { latitude: 50.3401, longitude: 4.9062 }
        end.not_to change(MapFeature, :count)

        expect(JSON.parse(response.body)).to include("moved" => true, "map_feature_id" => feature_id)
        expect(reinette.reload.map_feature.geometry["coordinates"]).to eq([4.9062, 50.3401])
      end

      it "garde un statut métier autre que « à placer »" do
        medlar.update!(status: "planted")
        post place_plant_path(medlar), headers: json, params: { latitude: 50.34, longitude: 4.905 }
        expect(medlar.reload.status).to eq("planted")
      end

      it "rouvre la fiche placée en Turbo Stream" do
        post place_plant_path(reinette), headers: turbo, params: { latitude: 50.34, longitude: 4.905 }
        expect(response.body).to include("turbo-stream", %(data-feature-saved="true"), "Retirer de la carte")
      end

      it "refuse des coordonnées illisibles ou hors du globe (422), sans rien écrire" do
        [{ latitude: "abc", longitude: "4.9" }, { latitude: "50.3" }, { latitude: "95", longitude: "4.9" },
         { latitude: "50.3", longitude: "Infinity" }].each do |params|
          expect do
            post place_plant_path(reinette), headers: json, params: params
          end.not_to change(MapFeature, :count)
          expect(response).to have_http_status(:unprocessable_content)
          expect(JSON.parse(response.body)["error"]).to include("Position illisible")
        end
        expect(reinette.reload.status).to eq("to_place")
      end

      it "« Annuler » en JSON rend la plante à la liste" do
        post place_plant_path(reinette), headers: json, params: { latitude: 50.34, longitude: 4.905 }
        post unplace_plant_path(reinette), headers: json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include("remaining" => 3, "map_feature_id" => nil, "status" => "to_place")
        expect(reinette.reload.map_feature).to be_nil
      end
    end
  end
end
