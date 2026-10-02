require "rails_helper"

# Le relief du domaine en 3D et la simulation du ruissellement. La page ne fait
# que servir des réglages et deux fichiers (le MNT en binaire, l'ortho) : tout
# le calcul se joue dans le navigateur.
RSpec.describe "Carte du domaine — relief 3D", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-relief@les4sources.be", password: "password123") }
  let(:root) { Pathname(Dir.mktmpdir("map-terrain")) }
  let(:terrain) { Maps::Terrain.new(root: root) }

  before { allow(Maps::Terrain).to receive(:current).and_return(terrain) }
  after { FileUtils.rm_rf(root) }

  def install_terrain(texture: true, surface: true)
    FileUtils.mkdir_p(root)
    File.binwrite(terrain.grid_path, [0, 100, 200, 300].pack("v*"))
    File.binwrite(terrain.texture_path, "\xFF\xD8fake".b) if texture
    File.binwrite(terrain.surface_path, [500, 600, 700, 800].pack("v*")) if surface
    File.binwrite(terrain.landcover_path, [7, 7, 9, 2].pack("C*")) if surface
    File.write(terrain.metadata_path, {
      cols: 2, rows: 2, west: 545_000.0, north: 6_506_000.0, step: 1.5669, cell_size_m: 1.0,
      z_min: 120.0, z_max: 123.0, z_unit: 0.01, nodata: 65_535, fetched_at: "2026-10-01T00:06:15+02:00",
      surface: (surface ? { z_min: 120.0, z_max: 128.0, z_unit: 0.01, nodata_count: 0 } : nil),
      landcover: (surface ? { nodata: 255, classes: { "7" => "Prairie permanente" } } : nil)
    }.compact.to_json)
  end

  it "exige une session" do
    get map_relief_path

    expect(response).to redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    it "explique comment installer le relief tant qu'il manque" do
      get map_relief_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("rake map:terrain:import")
      expect(response.body).not_to include('data-controller="map-relief"')
    end

    it "monte la scène avec la grille, l'ortho et les couches à dessiner" do
      install_terrain
      management = MapLayer.for_kind(:management)
      MapLayer.for_kind(:comments)

      get map_relief_path

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      scene = page.at_css('[data-controller="map-relief"]')
      expect(scene["data-map-relief-grid-url-value"]).to start_with("/map/relief/grid?v=")
      expect(scene["data-map-relief-texture-url-value"]).to start_with("/map/relief/texture?v=")
      expect(JSON.parse(scene["data-map-relief-meta-value"])).to include("cols" => 2, "rows" => 2, "z_min" => 120.0)
      expect(scene["data-map-relief-surface-url-value"]).to start_with("/map/relief/surface?v=")
      expect(JSON.parse(scene["data-map-relief-surface-meta-value"])).to eq("z_min" => 120.0, "z_unit" => 0.01)
      expect(page.at_css('[data-choice-group="sunMode"]')).to be_present
      expect(page.at_css('[data-map-relief-value-param="canopy"]')).to be_present
      expect(scene["data-map-relief-landcover-url-value"]).to start_with("/map/relief/landcover?v=")
      expect(page.at_css('[data-map-relief-value-param="landcover"]')).to be_present
      expect(page.at_css('[data-choice-group="rainSource"]')).to be_present
      expect(page.at_css('[data-choice-group="soilState"]')).to be_present
      # Les fonds de station, pour placer les espèces.
      %w[aspect wetness frost].each do |kind|
        expect(page.at_css(%([data-map-relief-value-param="#{kind}"]))).to be_present
      end
      layers = JSON.parse(scene["data-map-relief-feature-layers-value"])
      expect(layers.map { |layer| layer["id"] }).to include(management.id)
      expect(layers.map { |layer| layer["kind"] }).not_to include("comments")
    end

    it "sert la grille en binaire et l'ortho en JPEG, avec un long cache" do
      install_terrain

      get map_relief_grid_path(v: "x")
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/octet-stream")
      expect(response.body.b.unpack("v*")).to eq([0, 100, 200, 300])
      expect(response.headers["Cache-Control"]).to include("immutable")

      get map_relief_texture_path(v: "x")
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/jpeg")

      get map_relief_surface_path(v: "x")
      expect(response).to have_http_status(:ok)
      expect(response.body.b.unpack("v*")).to eq([500, 600, 700, 800])

      get map_relief_landcover_path(v: "x")
      expect(response).to have_http_status(:ok)
      expect(response.body.b.unpack("C*")).to eq([7, 7, 9, 2])
    end

    it "répond 404, sans erreur, quand les fichiers manquent" do
      get map_relief_grid_path
      expect(response).to have_http_status(:not_found)

      install_terrain(texture: false, surface: false)
      get map_relief_texture_path
      expect(response).to have_http_status(:not_found)
      get map_relief_surface_path
      expect(response).to have_http_status(:not_found)
    end

    # Sans modèle de surface, la page tient : pas de « Végétation », pas
    # d'arbres en relief, et un mot pour dire que les ombres ne viennent que du
    # relief.
    it "se passe du modèle de surface quand il manque" do
      install_terrain(surface: false)

      get map_relief_path

      page = Nokogiri::HTML(response.body)
      expect(page.at_css('[data-controller="map-relief"]')["data-map-relief-surface-url-value"]).to eq("")
      expect(page.at_css('[data-map-relief-value-param="canopy"]')).to be_nil
      expect(response.body).to include("seules les ombres du relief comptent")
    end

    it "se rejoint depuis la carte et depuis la barre des pages annexes" do
      get map_carnet_path
      expect(response.body).to include(%(href="#{map_relief_path}"))
    end
  end
end
