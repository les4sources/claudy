require "rails_helper"

# La carte en lecture seule (rôle Kid, Michael 2026-10-12) : Kid consulte la
# carte et ses fiches, sans aucun geste d'écriture proposé.
RSpec.describe "Carte du domaine — lecture seule", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:html) { Nokogiri::HTML(response.body) }
  let(:apple) { PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica") }
  let(:plant) { Plant.create!(name: "Pommier du haut", number: 42, plant_species: apple).tap { |p| p.place!(latitude: 50.34, longitude: 4.905) } }

  before do
    MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                         bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
    MapLayer.for_kind(:plants)
    MapLayer.for_kind(:comments)
  end

  context "Kid" do
    before { sign_in User.create!(email: "kid@les4sources.be", password: "password123", access_roles: %w[kid]) }

    it "ouvre la carte en lecture seule, sans pose au toucher ni création de plante" do
      get map_path
      expect(response).to have_http_status(:ok)
      expect(html.at_css("body")["class"].to_s.split).to include("map-read-only")
      expect(html.at_css("[data-controller='map']")["data-map-read-only-value"]).to eq("true")
      expect(html.at_css("[data-layer-extra='comments']")["data-new-comment-url"]).to be_nil
      expect(html.at_css("[data-layer-extra='plants']")["data-map-edit"]).to eq("true")
    end

    it "lit la fiche d'une plante, formulaire désactivé et sans geste de placement" do
      get plant_path(plant)
      expect(response).to have_http_status(:ok)
      expect(html.at_css("fieldset[disabled][data-map-read-only] form")).to be_present
      expect(response.body).not_to include("Déplacer", "+ Ajouter une tâche")
    end
  end

  context "Sourcier" do
    before { sign_in User.create!(email: "michael@les4sources.be", password: "password123") }

    it "garde tous les gestes d'écriture" do
      get map_path
      expect(html.at_css("body")["class"].to_s.split).not_to include("map-read-only")
      expect(html.at_css("[data-controller='map']")["data-map-read-only-value"]).to eq("false")
      expect(html.at_css("[data-layer-extra='comments']")["data-new-comment-url"]).to be_present

      get plant_path(plant)
      expect(html.at_css("fieldset[data-map-read-only]")).to be_nil
      expect(response.body).to include("Déplacer", "+ Ajouter une tâche")
    end
  end
end
