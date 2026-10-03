require "rails_helper"

# « Nouvelle plante » : un spécimen qu'on vient de mettre en terre, parfois
# d'une espèce que la base ne connaît pas encore. La fiche vide s'ouvre dans le
# panneau de la carte, l'espèce se crée par son nom, et la plante naît sans
# point — prête à être posée.
RSpec.describe "Carte du domaine — nouvelle plante", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-nouvelle-plante@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  it "exige une session Devise" do
    get new_plant_path
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    it "ouvre une fiche vide dans la frame du panneau, plantée aujourd'hui" do
      get new_plant_path(zone: "Verger")

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include(%(<turbo-frame id="#{MapFeaturesController::PANEL_FRAME}"))
      expect(body).to include(%(data-plant-panel="new"), "Nouvelle plante", "Créer la plante")
      expect(body).to include(%(action="#{plants_path}"), %(value="#{Date.current.iso8601}"), %(value="Verger"))
      expect(body).to include("Une espèce absente de la liste se crée à l&#39;enregistrement.")
      expect(body).not_to include("Supprimer la plante")
    end

    # Sur iPhone, « Prendre une photo » n'en rend qu'une : les photos s'ajoutent
    # l'une après l'autre (`photo-picker`) et partent avec « Créer la plante ».
    it "propose d'ajouter plusieurs photos dès la création, envoyées avec « Créer la plante »" do
      get new_plant_path
      html = Nokogiri::HTML(response.body)
      section = html.at_css(%([data-plant-section="photos"]))
      picker = section.at_css(%([data-controller="photo-picker"]))
      expect(picker["data-photo-picker-save-label-value"]).to eq("Créer la plante")

      field = picker.at_css(%(input[type=file][data-photo-picker-target="field"]))
      expect(field["name"]).to eq("plant[photos][]")
      expect(field["form"]).to eq(html.at_css("form[data-plant-form]")["id"])
      expect(field["multiple"]).to be_present

      # Le champ qu'ouvre le bouton n'a pas de `name` : seul `field` part.
      button = picker.at_css(%(input[type=file][data-photo-picker-target="picker"]))
      expect(button["name"]).to be_nil
      expect(button["multiple"]).not_to be_nil
      expect(button["data-action"]).to eq("change->photo-picker#add")
    end

    it "crée la plante avec ses photos, envoyées ensemble" do
      png = fixture_file_upload(Rails.root.join("spec/fixtures/files/map-tiles/test-layer/rgb/12/2103/1383.png"), "image/png")
      post plants_path, headers: turbo, params: { plant: { species_name: "Kaki", status: "planted", photos: [png, png, png] } }

      expect(response).to have_http_status(:ok)
      expect(Plant.last.photos.count).to eq(3)
    end

    it "crée la plante et son espèce inconnue par leur nom, sans point sur la carte" do
      expect do
        post plants_path, headers: turbo, params: {
          plant: { name: "", species_name: "  Kaki  ", variety_name: "Fuyu", zone: "Verger", number: "#97",
                   status: "planted", planted_on: "2026-09-28" }
        }
      end.to change(Plant, :count).by(1).and change(PlantSpecies, :count).by(1)

      expect(response).to have_http_status(:ok)
      plant = Plant.last
      expect(plant.plant_species.name).to eq("Kaki")
      expect(plant.plant_variety.name).to eq("Fuyu")
      expect(plant.name).to be_present
      expect(plant).to have_attributes(number: 97, zone: "Verger", status: "planted", created_by: user,
                                       planted_on: Date.new(2026, 9, 28), planted_year: 2026, map_feature_id: nil)
      expect(Plant.alive.to_place).to include(plant)

      body = response.body
      expect(body).to include(%(data-plant-panel="#{plant.id}"), %(data-plant-created="true"), "Plante créée.")
      expect(body).to include("Placer sur la carte", "Je suis devant", %(data-plant-section="photos"))
      # Les boutons de placement lisent `dataset.plantId` : des tirets, pas des `_`.
      expect(body).to include(%(data-plant-id="#{plant.id}"), %(data-plant-name="#{plant.name}"), "data-plant-place")
      expect(body).not_to include("data-plant_id")
    end

    it "réutilise une espèce existante sans la dupliquer (casse et accents indifférents)" do
      PlantSpecies.create!(name: "Néflier")

      expect do
        post plants_path, headers: turbo, params: { plant: { species_name: "néflier", status: "planted" } }
      end.to change(Plant, :count).by(1).and change(PlantSpecies, :count).by(0)
    end

    it "refuse une plante sans nom ni espèce et garde la fiche de création" do
      expect do
        post plants_path, headers: turbo, params: { plant: { name: "", species_name: "", status: "planted" } }
      end.not_to change(Plant, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(%(data-plant-panel="new"), %(action="#{plants_path}"), "Créer la plante")
    end

    it "annule l'espèce créée quand la plante est refusée" do
      expect do
        post plants_path, headers: turbo, params: { plant: { species_name: "Goji", number: "-3", status: "planted" } }
      end.not_to change(PlantSpecies, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(%(value="Goji"))
    end

    it "la carte ouvre la fiche vide depuis `/map?plant=new`, et la liste y renvoie" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      get map_path(plant: "new")
      expect(response.body).to include(%(data-map-open-new-plant-value="true"), %(data-map-new-plant-url-value="#{new_plant_path}"))
      expect(response.body).to include(%(data-map-new-plant-link="true"), %(data-placement-new-plant="true"))

      get map_path
      expect(response.body).not_to include("data-map-open-new-plant-value")

      get map_plantes_path
      expect(response.body).to include(%(href="#{map_path(plant: 'new')}"), "Nouvelle plante")
    end
  end
end
