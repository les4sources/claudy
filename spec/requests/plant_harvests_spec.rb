require "rails_helper"

# Epic #348, phase 7 — le calendrier de récolte sur la fiche plante : grille
# parties × mois, héritage de l'espèce, personnalisation, édition de
# l'ensemble, retour à l'espèce. Chaque geste remplace la seule section.
RSpec.describe "Carte du domaine — calendrier de récolte d'une plante (epic #348, phase 7)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "agent-recoltes@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:apple) { PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica") }
  let(:plant) { Plant.create!(name: "Pommier du haut", plant_species: apple, zone: "Verger") }

  def section(body = response.body)
    Nokogiri::HTML(body).at_css(%([data-plant-section="harvest"]))
  end

  def active_months(node, part)
    node.css(%([data-harvest-part="#{part}"] [data-active="true"])).map { |cell| cell["data-month"].to_i }
  end

  it "exige une session Devise" do
    patch plant_harvest_path(plant), headers: turbo, params: { harvest: { parts: { fruit: ["9"] } } }
    expect(plant.harvest_windows.count).to eq(0)
  end

  context "connecté" do
    before { sign_in user }

    describe "la grille de la fiche" do
      it "montre le calendrier hérité de l'espèce, avec le bouton pour le personnaliser" do
        apple.harvest_windows.create!(part: "fruit", months: [9, 10])
        apple.harvest_windows.create!(part: "flower", months: [4])

        travel_to(Date.new(2026, 9, 15)) { get plant_path(plant) }

        node = section
        expect(node["data-harvest-inherited"]).to eq("true")
        expect(node.text).to include("Calendrier de l'espèce Pommier", "Personnaliser pour cette plante")
        expect(active_months(node, "fruit")).to eq([9, 10])
        expect(active_months(node, "flower")).to eq([4])
        # Fleur avant fruit : l'ordre des parties.
        expect(node.css("[data-harvest-part]").map { |row| row["data-harvest-part"] }).to eq(%w[flower fruit])
        expect(node.at_css(%([data-current-month="true"])).text.strip).to eq("S")
        expect(node.text).not_to include("Revenir au calendrier de l'espèce")
      end

      it "propose d'ajouter une partie quand ni la plante ni l'espèce n'ont de calendrier" do
        get plant_path(plant)

        node = section
        expect(node.text).to include("Aucun calendrier de récolte", "Ajouter une partie")
        expect(node.css("[data-harvest-part]")).to be_empty
        expect(node.at_css(%(form[action="#{plant_harvest_path(plant)}"]))).to be_present
      end
    end

    describe "POST customize" do
      it "copie toutes les fenêtres de l'espèce sur la plante et ouvre l'édition" do
        apple.harvest_windows.create!(part: "fruit", months: [9, 10])
        apple.harvest_windows.create!(part: "leaf", months: [5])

        post customize_plant_harvest_path(plant), headers: turbo

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include(%(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(plant, :harvest)}">))
        expect(plant.harvest_windows.reload.map { |w| [w.part, w.months] }).to eq([["leaf", [5]], ["fruit", [9, 10]]])
        expect(apple.harvest_windows.count).to eq(2)
        node = section
        expect(node["data-harvest-inherited"]).to be_nil
        expect(node.at_css("details[open]")).to be_present
        expect(node.text).to include("Revenir au calendrier de l'espèce")
      end

      it "ne duplique rien si la plante a déjà son calendrier" do
        apple.harvest_windows.create!(part: "fruit", months: [9])
        plant.harvest_windows.create!(part: "fruit", months: [8])

        post customize_plant_harvest_path(plant), headers: turbo

        expect(plant.harvest_windows.reload.map(&:months)).to eq([[8]])
      end
    end

    describe "PATCH (remplace l'ensemble des fenêtres propres)" do
      it "enregistre les parties envoyées et supprime les autres" do
        plant.harvest_windows.create!(part: "fruit", months: [9])
        plant.harvest_windows.create!(part: "flower", months: [4])

        patch plant_harvest_path(plant), headers: turbo, params: {
          harvest: { parts: { fruit: ["", "8", "9", "10"], seed: ["", "11"], bogus: ["1"] } }
        }

        expect(response).to have_http_status(:ok)
        expect(plant.harvest_windows.reload.map { |w| [w.part, w.months] }).to eq([["fruit", [8, 9, 10]], ["seed", [11]]])
        expect(active_months(section, "fruit")).to eq([8, 9, 10])
      end

      it "refuse lisiblement (422) une partie sans mois, sans rien toucher" do
        plant.harvest_windows.create!(part: "fruit", months: [9])

        patch plant_harvest_path(plant), headers: turbo, params: { harvest: { parts: { fruit: ["", "10"], leaf: [""] } } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Feuille : cochez au moins un mois, ou retirez la partie.")
        expect(plant.harvest_windows.reload.map(&:months)).to eq([[9]])
        # L'éditeur reste ouvert sur la saisie : la feuille y est, active.
        node = section
        expect(node.at_css("details[open]")).to be_present
        expect(node.at_css(%(fieldset[data-part="leaf"]))["disabled"]).to be_nil
        expect(node.at_css(%(input[name="harvest[parts][fruit][]"][value="10"]))["checked"]).to be_present
      end

      it "refuse un mois hors calendrier (422) et annule toute l'opération" do
        plant.harvest_windows.create!(part: "fruit", months: [9])

        patch plant_harvest_path(plant), headers: turbo, params: { harvest: { parts: { fruit: ["13"] } } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Fruit : les mois doivent être compris entre 1 et 12.")
        expect(plant.harvest_windows.reload.map(&:months)).to eq([[9]])
      end
    end

    describe "DELETE (retour au calendrier de l'espèce)" do
      it "supprime les fenêtres propres : la plante hérite de nouveau" do
        apple.harvest_windows.create!(part: "fruit", months: [9, 10])
        plant.harvest_windows.create!(part: "fruit", months: [7])

        delete plant_harvest_path(plant), headers: turbo

        expect(response).to have_http_status(:ok)
        expect(plant.harvest_windows.reload).to be_empty
        expect(apple.harvest_windows.count).to eq(1)
        node = section
        expect(node["data-harvest-inherited"]).to eq("true")
        expect(active_months(node, "fruit")).to eq([9, 10])
      end
    end

    it "ne touche pas une plante supprimée" do
      plant.soft_delete!(validate: false)
      expect { post customize_plant_harvest_path(plant), headers: turbo }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
