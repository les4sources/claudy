require "rails_helper"

# Epic #348, phase 7 — le catalogue des espèces (`/map/especes`) : liste,
# fiche éditable, calendrier de récolte par défaut, variétés, suppression
# refusée tant que des plantes vivantes en dépendent. L'autocomplétion JSON
# reste sur `/map/species.json`.
RSpec.describe "Carte du domaine — espèces (epic #348, phase 7)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-especes@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:html) { Nokogiri::HTML(response.body) }
  let!(:apple) { PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica", family: "Rosacées") }
  let!(:medlar) { PlantSpecies.create!(name: "Néflier") }
  let!(:reinette) { apple.varieties.create!(name: "Reinette Hernaut") }
  let!(:tree) { Plant.create!(name: "Pommier du verger", number: 7, plant_species: apple, plant_variety: reinette) }

  it "exige une session Devise" do
    get map_especes_path
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    describe "la liste" do
      it "liste les espèces avec nom latin, famille, plantes vivantes et mini-calendrier" do
        apple.harvest_windows.create!(part: "fruit", months: [9, 10])
        Plant.create!(name: "Pommier mort", plant_species: apple, status: "dead")

        get map_especes_path

        expect(response).to have_http_status(:ok)
        row = html.at_css("li[data-species-id='#{apple.id}']")
        expect(row.text).to include("Pommier", "Malus domestica", "Rosacées", "1 à placer")
        expect(row.at_css("[data-plant-count]")["data-plant-count"]).to eq("1")
        expect(row.at_css("[data-mini-harvest='fruit']")).to be_present
        expect(html.at_css("li[data-species-id='#{medlar.id}']").text).to include("Pas de calendrier")
        expect(html.at_css("nav[data-map-subnav] a[aria-current='page']").text).to include("Espèces")
      end

      it "cherche par nom ou nom latin" do
        get map_especes_path(q: "malus")
        expect(response.body).to include("Pommier")
        expect(response.body).not_to include("Néflier")
      end

      it "garde l'autocomplétion JSON sur /map/species.json" do
        get map_species_path(format: :json, q: "pom"), headers: { "Accept" => "application/json" }
        expect(JSON.parse(response.body).map { |s| s["name"] }).to eq(["Pommier"])
      end
    end

    describe "la fiche" do
      it "montre calendrier, fiche botanique, variétés et plantes" do
        get map_espece_path(apple)

        expect(response).to have_http_status(:ok)
        expect(html.css("[data-species-section]").map { |s| s["data-species-section"] })
          .to eq(%w[harvest identity varieties plants])
        expect(html.at_css("[data-variety-id='#{reinette.id}'] input[type=text]")["value"]).to eq("Reinette Hernaut")
        expect(html.at_css("a[data-species-plant='#{tree.id}']")["href"]).to eq(map_path(plant: tree.id))
        expect(response.body).to include("ne peut pas être supprimée")
      end

      it "enregistre la fiche botanique" do
        patch map_espece_path(apple), params: {
          plant_species: { name: "Pommier domestique", hardiness: "-25 °C", height: "5 m", spread: "4 m",
                           common_names: "Pommier cultivé", wikipedia_url: "https://fr.wikipedia.org/wiki/Pommier",
                           exposure: ["", "Soleil", "Mi-ombre"], edible_parts: ["", "Fruit", "Fleur"], notes: "Taille d'hiver." }
        }

        expect(response).to redirect_to(map_espece_path(apple))
        expect(apple.reload).to have_attributes(name: "Pommier domestique", hardiness: "-25 °C", height: "5 m",
                                                exposure: %w[Soleil Mi-ombre], edible_parts: %w[Fruit Fleur])
      end

      it "refuse un nom déjà pris (422)" do
        patch map_espece_path(apple), params: { plant_species: { name: "néflier" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("existe déjà dans le catalogue")
      end
    end

    describe "le calendrier de récolte par défaut" do
      it "remplace les fenêtres de l'espèce et répond en Turbo Stream" do
        apple.harvest_windows.create!(part: "flower", months: [4])
        patch map_espece_harvest_path(apple), headers: turbo,
                                              params: { harvest: { parts: { fruit: ["", "9", "10"] } } }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("turbo-stream", "harvest_plant_species_#{apple.id}")
        expect(apple.reload.harvest_windows.map { |w| [w.part, w.months] }).to eq([["fruit", [9, 10]]])
        # La plante sans calendrier propre suit.
        expect(tree.reload.harvest_months).to eq([9, 10])
      end

      it "refuse une partie sans mois (422), sans rien effacer" do
        apple.harvest_windows.create!(part: "flower", months: [4])
        patch map_espece_harvest_path(apple), headers: turbo, params: { harvest: { parts: { fruit: [""] } } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("cochez au moins un mois")
        expect(apple.reload.harvest_windows.map(&:part)).to eq(["flower"])
      end

      it "s'efface" do
        apple.harvest_windows.create!(part: "fruit", months: [9])
        delete map_espece_harvest_path(apple), headers: turbo
        expect(apple.reload.harvest_windows).to be_empty
      end
    end

    describe "les variétés" do
      it "s'ajoutent, se renomment, refusent un doublon" do
        post map_espece_varieties_path(apple), params: { plant_variety: { name: "Boskoop" } }
        expect(response).to redirect_to(map_espece_path(apple, anchor: "varietes"))
        boskoop = apple.varieties.find_by!(name: "Boskoop")

        patch map_espece_variety_path(apple, boskoop), params: { plant_variety: { name: "Belle de Boskoop" } }
        expect(boskoop.reload.name).to eq("Belle de Boskoop")

        post map_espece_varieties_path(apple), params: { plant_variety: { name: "reinette hernaut" } }
        expect(flash[:alert]).to include("existe déjà pour cette espèce")
        expect(apple.varieties.count).to eq(2)
      end

      it "ne se supprime pas tant qu'une plante vivante la porte" do
        delete map_espece_variety_path(apple, reinette)
        expect(flash[:alert]).to include("changez-leur de variété")
        expect(PlantVariety.find_by(id: reinette.id)).to be_present
      end
    end

    describe "la suppression" do
      it "est refusée tant que des plantes vivantes en dépendent" do
        delete map_espece_path(apple)
        expect(response).to redirect_to(map_espece_path(apple))
        expect(flash[:alert]).to include("Impossible de supprimer « Pommier » : 1 plante vivante en dépend.")
        expect(PlantSpecies.find_by(id: apple.id)).to be_present
      end

      it "retire une espèce sans plante vivante" do
        tree.update!(status: "dead")
        delete map_espece_path(apple)
        expect(response).to redirect_to(map_especes_path)
        expect(PlantSpecies.find_by(id: apple.id)).to be_nil
      end
    end
  end
end
