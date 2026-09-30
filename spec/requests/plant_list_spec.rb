require "rails_helper"

# Epic #348, phase 7 — la liste de toutes les plantes (`GET /map/plantes`) :
# compteurs, recherche, filtres, tri par numéro, liens vers la carte ; et la
# barre de navigation commune des pages annexes.
RSpec.describe "Carte du domaine — liste des plantes (epic #348, phase 7)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-liste@les4sources.be", password: "password123") }
  def html = Nokogiri::HTML(response.body)
  let(:apple) { PlantSpecies.create!(name: "Pommier") }
  let!(:placed) do
    Plant.create!(name: "Pommier du verger", number: 5, plant_species: apple, zone: "Verger", health: "healthy", stratum: "tree")
         .place!(latitude: 50.34, longitude: 4.905)
  end
  let!(:waiting) { Plant.create!(name: "Groseillier", number: 2, zone: "Potager", health: "sick", stratum: "shrub", status: "to_place") }
  let!(:dead) { Plant.create!(name: "Figuier gelé", number: 9, zone: "Verger", status: "dead") }

  def row_ids = html.css("li[data-plant-row]").map { |li| li["data-plant-row"].to_i }

  it "exige une session Devise" do
    get map_plantes_path
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    it "liste toutes les plantes par numéro, avec les compteurs du domaine" do
      get map_plantes_path

      expect(response).to have_http_status(:ok)
      expect(row_ids).to eq([waiting.id, placed.id, dead.id])
      counters = html.css("[data-plant-counter]").to_h { |a| [a["data-plant-counter"], a.at_css("span").text.to_i] }
      expect(counters).to eq("total" => 3, "placed" => 1, "to_place" => 1, "dead" => 1)
      expect(html.at_css("li[data-plant-row='#{placed.id}'] a")["href"]).to eq(map_path(feature: placed.map_feature_id))
      expect(html.at_css("li[data-plant-row='#{waiting.id}'] a")["href"]).to eq(map_path(plant: waiting.id))
      expect(html.at_css("li[data-plant-row='#{placed.id}']").text).to include("#5", "Pommier", "Verger", "Saine", "placée")
    end

    it "filtre par recherche, statut, santé, zone, strate et placement" do
      get map_plantes_path(q: "pommier")
      expect(row_ids).to eq([placed.id])

      get map_plantes_path(status: "dead")
      expect(row_ids).to eq([dead.id])

      get map_plantes_path(health: "sick")
      expect(row_ids).to eq([waiting.id])

      get map_plantes_path(zone: "Verger")
      expect(row_ids).to eq([placed.id, dead.id])

      get map_plantes_path(stratum: "shrub")
      expect(row_ids).to eq([waiting.id])

      get map_plantes_path(placed: "yes")
      expect(row_ids).to eq([placed.id])

      # « À placer » : les vivantes sans point, pas la morte.
      get map_plantes_path(placed: "no")
      expect(row_ids).to eq([waiting.id])
      expect(html.at_css("a[data-plant-counter='to_place']")["aria-current"]).to eq("page")
    end

    it "ignore les valeurs de filtre inconnues" do
      get map_plantes_path(status: "bogus", zone: "Nulle part", placed: "maybe")
      expect(row_ids.size).to eq(3)
    end

    it "partage la barre Carte · Carnet · Récoltes · Plantes · Espèces · Biodiversité · Relief 3D avec les autres pages annexes" do
      { map_carnet_path => "Carnet", map_recoltes_path => "Récoltes", map_plantes_path => "Plantes",
        map_especes_path => "Espèces", map_biodiversite_path => "Biodiversité" }.each do |path, label|
        get path
        nav = html.at_css("nav[data-map-subnav]")
        expect(nav.css("a").map(&:text).map(&:strip)).to eq(["Carte", "Carnet", "Récoltes", "Plantes", "Espèces", "Biodiversité", "Relief 3D"])
        expect(nav.at_css("a[aria-current='page']").text.strip).to eq(label)
      end
    end

    it "a ses entrées dans le panneau de la carte" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      get map_path
      expect(html.at_css(%(a[data-map-plantes-link][href="#{map_plantes_path}"]))).to be_present
      expect(html.at_css(%(a[data-map-especes-link][href="#{map_especes_path}"]))).to be_present
    end
  end
end
