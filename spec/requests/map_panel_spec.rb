require "rails_helper"

# Le panneau de la carte en deux onglets (Michael, 2026-10-03) : « Travailler »
# (couche active et ses actions), « Afficher » (fond, relief, Géoportail,
# filtres), les pages annexes en pied de panneau.
RSpec.describe "Carte du domaine — panneau en deux onglets", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-panneau@les4sources.be", password: "password123") }
  let(:html) { Nokogiri::HTML(response.body) }

  before do
    sign_in user
    MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                         bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
    MapLayer.for_kind(:plants)
  end

  def pane(key) = html.at_css("[role='tabpanel'][data-panel-tab='#{key}']")

  it "propose deux onglets, « Travailler » ouvert" do
    get map_path
    expect(response).to have_http_status(:ok)

    tabs = html.css("[role='tablist'] [role='tab']")
    expect(tabs.map { |tab| tab.text.strip }).to eq(%w[Travailler Afficher])
    expect(tabs.map { |tab| tab["aria-selected"] }).to eq(%w[true false])
    expect(pane("work")["class"].to_s.split).not_to include("hidden")
    expect(pane("see")["class"].to_s.split).to include("hidden")
  end

  it "range les couches, les réseaux et les notes dans « Travailler »" do
    get map_path
    work = pane("work")
    expect(work.css("button[data-map-target='layerName']").map { |b| b.text.strip }).to include("Électricité")
    expect(work.at_css("[data-map-networks-section]")).to be_present
    expect(work.at_css("[data-map-sketches]")).to be_present
    expect(work.at_css("[data-layer-extra='comments'] input[data-comments-filter]")).to be_present
  end

  it "met « Nouvelle plante » et « À placer » sous la couche des plantes, avec elle seulement" do
    get map_path
    extra = pane("work").at_css("li[data-layer-extra='plants']")
    expect(extra["class"].to_s.split).to include("hidden")
    expect(extra.at_css("[data-map-new-plant-link][data-action='map#newPlant']")).to be_present
    expect(extra.at_css("[data-map-placement-link][data-action='map#openPlacement']")).to be_present
    # Le nombre de plantes à placer reste en vue sur la ligne de la couche.
    expect(pane("work").at_css("button[data-layer-kind='plants'] [data-map-target='unplacedCount']")).to be_present
  end

  it "range le fond, le Géoportail replié par groupe et « ce mois-ci » dans « Afficher »" do
    get map_path
    see = pane("see")
    expect(see.at_css("a[href*='base_layer_id']").text).to include("Couche de test")
    groups = see.css("details")
    expect(groups.map { |g| g.css("summary span").map { |s| s.text.strip } }).to eq(
      MapGeoportailLayer.grouped.map { |name, layers| [name, "0 / #{layers.size}"] }
    )
    groups.each { |group| expect(group["open"]).to be_nil }
    expect(see.css("input[data-action='change->map#toggleGeoportail']").size).to eq(MapGeoportailLayer.all.size)
    expect(see.at_css("input[data-map-month-toggle]")).to be_present
  end

  it "met les pages annexes en pied de panneau, hors des onglets" do
    get map_path
    nav = html.at_css("nav[data-map-pages]")
    expect(nav.css("a").map { |a| a.text.strip }).to eq(["Carnet", "Récoltes", "Plantes", "Espèces", "Biodiversité", "Relief 3D"])
    expect(nav.at_css(%(a[data-map-carnet-link][href="#{map_carnet_path}"]))).to be_present
    expect(nav.ancestors("[role='tabpanel']")).to be_empty
  end
end
