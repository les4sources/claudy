require "rails_helper"

# Les couches publiques du Géoportail de la Wallonie (SPW) superposées à la
# carte du domaine : Natura 2000, ortho 2026, sols, parcellaire agricole,
# cadastre, courbes de niveau. Servies en WMS par geoservices.wallonie.be,
# rien n'est stocké chez nous.
RSpec.describe "Carte du domaine — couches du Géoportail de Wallonie", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-geoportail@les4sources.be", password: "password123") }

  before { sign_in user }

  describe "MapGeoportailLayer" do
    it "liste les treize couches, chacune vers un WMSServer du SPW" do
      expect(MapGeoportailLayer.all.map(&:key)).to match_array(
        %w[ortho_2026 ortho_1994 ortho_1971 courbes pentes ruissellement sols essences
           natura2000 forets_anciennes plan_secteur cadastre parcellaire_agricole]
      )
      expect(MapGeoportailLayer.all.map(&:url))
        .to all(match(%r{\Ahttps://geoservices\.wallonie\.be/arcgis/services/[A-Z_]+/[A-Z0-9_]+/MapServer/WMSServer\z}))
    end

    it "empile les photos sous toutes les autres couches, chacune à son niveau" do
      photos, autres = MapGeoportailLayer.all.partition { |layer| layer.group == :photos }
      expect(autres.map(&:z_index).min).to be > photos.map(&:z_index).max
      expect(MapGeoportailLayer.all.map(&:z_index).uniq.size).to eq(MapGeoportailLayer.all.size)
    end

    it "range chaque couche dans un groupe du panneau" do
      expect(MapGeoportailLayer.grouped.map(&:first)).to eq(["Photos aériennes", "Relief, sol et eau", "Milieux et règles"])
      expect(MapGeoportailLayer.grouped.sum { |_, layers| layers.size }).to eq(MapGeoportailLayer.all.size)
    end
  end

  describe "la page /map" do
    it "propose une case par couche, avec tout ce qu'il faut pour la construire" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      get map_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Géoportail de Wallonie")
      expect(response.body.scan('data-action="change-&gt;map#toggleGeoportail"').size).to eq(MapGeoportailLayer.all.size)
      expect(response.body).to include(
        'data-geoportail-key="cadastre"',
        'data-geoportail-url="https://geoservices.wallonie.be/arcgis/services/PLAN_REGLEMENT/CADMAP_PARCELLES/MapServer/WMSServer"',
        'data-geoportail-z-index="14"'
      )
      expect(response.body).to include("Photos aériennes", "Relief, sol et eau", "Milieux et règles")
    end

    # L'information au clic : chaque couche sauf les photos dit quel service REST
    # interroger ; les courbes répondent par l'altitude du MNT.
    it "donne aux couches interrogeables le service à interroger au clic" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      get map_path

      expect(response.body.scan("data-geoportail-info-service=").size).to eq(MapGeoportailLayer.all.count(&:info_service))
      expect(MapGeoportailLayer.all.reject(&:info_service).map(&:group).uniq).to eq([:photos])
      expect(response.body).to include('data-geoportail-info-service="RELIEF/WALLONIE_MNT_2021_2022"')
      expect(response.body).to include("touchez la carte pour en lire le détail")
    end
  end
end
