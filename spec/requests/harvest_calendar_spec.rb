require "rails_helper"

# Epic #348, phase 7 — le calendrier des récoltes (`GET /map/recoltes`) : douze
# mois, les plantes qui s'y récoltent avec la partie, regroupées par espèce,
# filtres partie et zone, plantes mortes écartées, liens vers la carte.
RSpec.describe "Carte du domaine — calendrier des récoltes (epic #348, phase 7)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "agent-recoltes@les4sources.be", password: "password123") }
  let(:apple) { PlantSpecies.create!(name: "Pommier") }
  let(:elder) { PlantSpecies.create!(name: "Sureau") }
  let(:html) { Nokogiri::HTML(response.body) }

  before do
    apple.harvest_windows.create!(part: "fruit", months: [9, 10])
    elder.harvest_windows.create!(part: "flower", months: [6])
    elder.harvest_windows.create!(part: "fruit", months: [9])
  end

  let!(:reinette) { Plant.create!(name: "Pommier Reinette Hernaut", number: 4, plant_species: apple, zone: "Verger") }
  let!(:boskoop) { Plant.create!(name: "Pommier Boskoop", number: 2, plant_species: apple, zone: "Verger") }
  let!(:elderberry) { Plant.create!(name: "Sureau de la mare", plant_species: elder, zone: "Mare") }

  it "exige une session Devise" do
    get map_recoltes_path
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    it "rend douze mois, le mois courant ouvert et mis en avant" do
      travel_to Date.new(2026, 9, 15) do
        get map_recoltes_path
      end

      expect(response).to have_http_status(:ok)
      months = html.css("details[data-month]")
      expect(months.size).to eq(12)
      september = html.at_css("details[data-month='9']")
      expect(september.key?("open")).to be(true)
      expect(september["data-current-month"]).to eq("true")
      expect(html.at_css("details[data-month='3']").key?("open")).to be(false)
      expect(html.at_css("nav[data-map-subnav] a[aria-current='page']").text).to include("Récoltes")
    end

    it "regroupe les individus d'une espèce et compte les plantes du mois" do
      get map_recoltes_path

      september = html.at_css("details[data-month='9']")
      expect(september.at_css("[data-plant-count]")["data-plant-count"]).to eq("3")
      apples = september.at_css("[data-harvest-group='species-#{apple.id}-fruit']")
      expect(apples.text).to include("Pommier ×2", "fruit")
      # Le groupe se replie dans un vrai <summary> : une classe Tailwind à
      # crochets en notation courte Slim (`summary.min-h-[2.75rem]`) le cassait,
      # et tout le balisage s'affichait en texte.
      expect(apples.at_css("details > summary").text).to include("Pommier ×2")
      expect(apples.text).not_to include("cursor-pointer", "polyline")
      # Dans l'ordre des numéros.
      expect(apples.text.index("Pommier Boskoop")).to be < apples.text.index("Pommier Reinette Hernaut")

      june = html.at_css("details[data-month='6']")
      expect(june.text).to include("Sureau de la mare", "fleur")
      expect(june.text).not_to include("Pommier")
      expect(html.at_css("details[data-month='1']").text).to include("Rien à récolter")
    end

    it "suit le calendrier propre d'une plante plutôt que celui de son espèce" do
      reinette.harvest_windows.create!(part: "fruit", months: [8])
      get map_recoltes_path

      expect(html.at_css("details[data-month='8']").text).to include("Pommier Reinette Hernaut")
      expect(html.at_css("details[data-month='9'] [data-harvest-group='species-#{apple.id}-fruit']").text).not_to include("Reinette")
    end

    it "écarte les plantes mortes" do
      boskoop.update!(status: "dead")
      get map_recoltes_path
      expect(response.body).not_to include("Pommier Boskoop")
    end

    it "filtre par partie et par zone" do
      get map_recoltes_path(part: "flower")
      expect(html.at_css("details[data-month='9']").text).to include("Rien à récolter")
      expect(html.at_css("details[data-month='6']").text).to include("Sureau de la mare")
      expect(html.at_css("a[data-part-filter='flower']")["aria-current"]).to eq("page")

      get map_recoltes_path(zone: "Mare")
      expect(response.body).to include("Sureau de la mare")
      expect(response.body).not_to include("Pommier Boskoop")
    end

    it "mène à la plante sur la carte si elle est placée, à sa fiche sinon" do
      elderberry.place!(latitude: 50.34, longitude: 4.905)
      get map_recoltes_path

      links = html.css("details[data-month='6'] a[data-harvest-plant]").map { |a| a["href"] }
      expect(links).to eq([map_path(feature: elderberry.map_feature_id)])
      boskoop_link = html.at_css("a[data-harvest-plant='#{boskoop.id}']")
      expect(boskoop_link["href"]).to eq(map_path(plant: boskoop.id))
      expect(boskoop_link.text).to include("à placer")
    end

    it "a son entrée dans le panneau de la carte" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      get map_path
      expect(html.at_css(%(a[data-map-recoltes-link][href="#{map_recoltes_path}"]))).to be_present
    end
  end
end
