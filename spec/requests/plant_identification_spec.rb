require "rails_helper"

# « Placer une plante » : une ou plusieurs photos d'un individu partent chez
# Pl@ntNet, les espèces probables reviennent dans la fiche, rapprochées du
# catalogue. On en valide une (le champ Espèce se remplit) ou on les refuse ;
# à l'enregistrement, une espèce nouvelle garde son nom latin et sa famille,
# et les photos rejoignent la plante — prête à être posée sur la carte.
RSpec.describe "Carte du domaine — identifier une plante par photo", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-identification@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:endpoint) { %r{\Ahttps://my-api\.plantnet\.org/v2/identify/all} }
  let(:photo) { fixture_file_upload("capture.png", "image/png") }

  around do |example|
    key = ENV["PLANTNET_API_KEY"]
    ENV["PLANTNET_API_KEY"] = "cle-test"
    example.run
  ensure
    ENV["PLANTNET_API_KEY"] = key
  end

  def stub_plantnet(*results)
    stub_request(:post, endpoint).to_return(status: 200, headers: { "Content-Type" => "application/json" },
                                            body: { results: results }.to_json)
  end

  def result(latin, score:, common: [], family: nil)
    { score: score, species: { scientificNameWithoutAuthor: latin, commonNames: common,
                               family: { scientificNameWithoutAuthor: family } } }
  end

  it "exige une session Devise" do
    post identify_plants_path, params: { photos: [photo] }
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
    expect(a_request(:any, endpoint)).not_to have_been_made
  end

  context "connecté" do
    before { sign_in user }

    it "propose le bouton photo sur la fiche d'une nouvelle plante" do
      get new_plant_path
      expect(response.body).to include(%(data-controller="plant-identify"), identify_plants_path,
                                       "Identifier l'espèce par photo", %(name="plant[species_latin_name]"))
    end

    it "désactive le bouton quand Pl@ntNet n'est pas configuré" do
      ENV["PLANTNET_API_KEY"] = nil
      get new_plant_path
      expect(response.body).to include("Identification par photo indisponible")
      expect(response.body).not_to include("change-&gt;plant-identify#identify")
    end

    it "rend les espèces probables, rapprochées du catalogue, et garde les photos à joindre" do
      apple = PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica 'Reinette'")
      medlar = PlantSpecies.create!(name: "Néflier")
      stub_plantnet(result("Malus domestica", score: 0.81, common: ["Pommier cultivé"], family: "Rosaceae"),
                    result("Mespilus germanica", score: 0.09, common: ["Néflier"], family: "Rosaceae"),
                    result("Malus sylvestris", score: 0.04, common: ["Pommier sauvage"], family: "Rosaceae"))

      expect { post identify_plants_path, params: { photos: [photo, photo] } }
        .to change(ActiveStorage::Blob, :count).by(2)

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include(%(data-name="Pommier"), %(data-species-id="#{apple.id}"))
      expect(body).to include(%(data-name="Néflier"), %(data-species-id="#{medlar.id}"))
      expect(body).to include(%(data-name="Pommier sauvage"), %(data-latin-name="Malus sylvestris"), %(data-family="Rosaceae"))
      expect(body).to include("81 %", "Au catalogue", "Nouvelle espèce", "C'est elle", "Identification : Pl@ntNet")
      expect(body.scan(%(name="plant[photos][]")).size).to eq(2)
      expect(body.index("Pommier")).to be < body.index("Pommier sauvage")
    end

    it "ne réutilise pas le nom d'une autre espèce du catalogue" do
      PlantSpecies.create!(name: "Sureau", latin_name: "Sambucus nigra")
      stub_plantnet(result("Sambucus racemosa", score: 0.6, common: ["Sureau"]))

      post identify_plants_path, params: { photos: [photo] }

      expect(response.body).to include(%(data-name="Sambucus racemosa"))
    end

    it "dit quand Pl@ntNet ne reconnaît aucune plante" do
      stub_request(:post, endpoint).to_return(status: 404, body: { message: "Species not found" }.to_json)
      post identify_plants_path, params: { photos: [photo] }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pl@ntNet ne reconnaît aucune plante")
    end

    it "refuse sans photo, ou un fichier qui n'est pas une photo, sans appeler Pl@ntNet" do
      post identify_plants_path
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choisissez au moins une photo")

      post identify_plants_path, params: { photos: [fixture_file_upload("unifi_devices.json", "application/json")] }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("n&#39;est pas une photo JPEG ou PNG")
      expect(a_request(:any, endpoint)).not_to have_been_made
    end

    it "rend l'erreur du service sans rien garder" do
      stub_request(:post, endpoint).to_return(status: 429, body: "Too many requests")
      expect { post identify_plants_path, params: { photos: [photo] } }.not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Pl@ntNet a répondu 429")
    end

    it "crée la plante avec l'espèce retenue, son nom latin, sa famille et les photos gardées" do
      blob = ActiveStorage::Blob.create_and_upload!(io: file_fixture("capture.png").open, filename: "feuille.png",
                                                    content_type: "image/png")

      expect do
        post plants_path, headers: turbo, params: {
          plant: { name: "", species_name: "Pommier sauvage", species_latin_name: "Malus sylvestris",
                   species_family: "Rosaceae", status: "planted", photos: [blob.signed_id] }
        }
      end.to change(Plant, :count).by(1).and change(PlantSpecies, :count).by(1)

      plant = Plant.last
      expect(plant.plant_species).to have_attributes(name: "Pommier sauvage", latin_name: "Malus sylvestris", family: "Rosaceae")
      expect(plant.photos.map(&:blob)).to eq([blob])
      expect(plant.map_feature_id).to be_nil
      expect(response.body).to include("Placer sur la carte", "Je suis devant")
    end

    it "ne réécrit pas le nom latin d'une espèce existante" do
      apple = PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica")

      post plants_path, headers: turbo, params: {
        plant: { species_name: "Pommier", species_latin_name: "Malus sylvestris", species_family: "Rosaceae", status: "planted" }
      }

      expect(Plant.last.plant_species).to eq(apple)
      expect(apple.reload).to have_attributes(latin_name: "Malus domestica", family: nil)
    end
  end
end
