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
    it "liste les six couches, chacune vers un WMSServer du SPW" do
      expect(MapGeoportailLayer.all.map(&:key))
        .to eq(%w[ortho_2026 sols natura2000 parcellaire_agricole cadastre courbes])
      expect(MapGeoportailLayer.all.map(&:url))
        .to all(match(%r{\Ahttps://geoservices\.wallonie\.be/arcgis/services/[A-Z_]+/[A-Z0-9_]+/MapServer/WMSServer\z}))
    end

    it "empile l'ortho sous toutes les autres couches" do
      ortho, *autres = MapGeoportailLayer.all
      expect(autres.map(&:z_index)).to all(be > ortho.z_index)
    end
  end

  describe "la page /map" do
    it "propose une case par couche, avec tout ce qu'il faut pour la construire" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      get map_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Géoportail de Wallonie")
      expect(response.body.scan('data-action="change-&gt;map#toggleGeoportail"').size).to eq(6)
      expect(response.body).to include(
        'data-geoportail-key="cadastre"',
        'data-geoportail-url="https://geoservices.wallonie.be/arcgis/services/PLAN_REGLEMENT/CADMAP_PARCELLES/MapServer/WMSServer"',
        'data-geoportail-z-index="13"'
      )
    end
  end
end
