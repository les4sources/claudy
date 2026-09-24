require "rails_helper"

# Epic #348, phase 4 — la couche Accueil : la carte que reçoivent les hôtes, à
# la place du papier. Côté équipe : une couche `welcome` qu'on trace comme la
# Gestion, des zones publiques / privées / sur demande, des points utiles à
# icône, et des textes en trois langues.
RSpec.describe "Carte du domaine — couche Accueil, côté équipe (epic #348, phase 4)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-accueil@les4sources.be", password: "password123") }
  let(:layer) { MapLayer.for_kind(:welcome) }
  let(:polygon) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end
  let(:point) { { "type" => "Point", "coordinates" => [4.9055, 50.3405] } }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before { sign_in user }

  describe "le modèle" do
    it "est une couche éditable" do
      expect(layer).to be_welcome
      expect(layer).to be_editable
    end

    it "exige un nom en français pour un objet d'accueil" do
      feature = layer.map_features.new(feature_kind: "zone", geometry: polygon, name_i18n: { "en" => "Orchard" })
      expect(feature).not_to be_valid

      feature.name_i18n = { "fr" => "Le verger" }
      expect(feature).to be_valid
    end

    it "n'exige pas de nom hors de la couche Accueil" do
      gestion = MapLayer.for_kind(:management)
      expect(gestion.map_features.new(feature_kind: "zone", geometry: polygon)).to be_valid
    end

    it "refuse un type de zone ou une icône inconnus" do
      feature = layer.map_features.new(feature_kind: "zone", geometry: polygon, name_i18n: { "fr" => "Pré" },
                                       properties: { "access" => "secret" })
      expect(feature).not_to be_valid

      feature.properties = { "icon" => "licorne" }
      expect(feature).not_to be_valid

      feature.properties = { "access" => "on_request", "icon" => "parking" }
      expect(feature).to be_valid
    end

    it "signale les langues à traduire, jamais le français" do
      feature = layer.map_features.create!(feature_kind: "zone", geometry: polygon,
                                           name_i18n: { "fr" => "Le verger", "en" => "The orchard" },
                                           description_i18n: { "fr" => "Cueillette libre" })
      expect(feature.missing_translations).to eq(%w[en nl])

      feature.update!(name_i18n: { "fr" => "Le verger", "en" => "The orchard", "nl" => "De boomgaard" },
                      description_i18n: { "fr" => "Cueillette libre", "en" => "Free picking", "nl" => "Vrij plukken" })
      expect(feature.missing_translations).to be_empty
    end

    it "ne montre à un hôte que la géométrie, le nom, la description et la nature, dans sa langue" do
      feature = layer.map_features.create!(feature_kind: "zone", geometry: polygon,
                                           name_i18n: { "fr" => "Le verger", "en" => "The orchard" },
                                           description_i18n: { "fr" => "Cueillette libre" },
                                           properties: { "access" => "public", "management_notes" => "Tailler en mars" })

      json = feature.as_public_geojson(:en)
      expect(json[:geometry]).to eq(polygon)
      expect(json[:properties]).to eq(name: "The orchard", description: "Cueillette libre", access: "public")
      expect(json.to_json).not_to include("Tailler en mars", feature.id.to_s)
    end
  end

  describe "la page /map" do
    it "crée la couche Accueil, la propose dans le panneau et affiche sa légende" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      get map_path

      expect(MapLayer.where(kind: "welcome").count).to eq(1)
      expect(response.body).to include('data-layer-kind="welcome"', 'data-map-target="welcomeLegend"')
      expect(response.body).to include("Accessible sur demande")
      # Point et ligne sont proposés à la couche Accueil comme à la Gestion.
      expect(response.body.scan('data-tool-kinds="management welcome"').size).to eq(2)
    end
  end

  describe "la fiche d'un objet d'accueil" do
    it "propose le type de zone et les traductions pour une zone" do
      get new_map_feature_path(layer_id: layer.id, feature_kind: "zone")

      expect(response.body).to include("Type de zone", "Nom — Français", "Nom — English", "Nom — Nederlands")
      expect(response.body).to include('name="map_feature[access]"')
      expect(response.body).not_to include('name="map_feature[icon]"', "Consigne de gestion")
    end

    it "propose l'icône pour un point" do
      get new_map_feature_path(layer_id: layer.id, feature_kind: "point")

      expect(response.body).to include('name="map_feature[icon]"', "Point de rendez-vous")
      expect(response.body).not_to include('name="map_feature[access]"')
    end

    it "crée une zone avec sa nature et ses trois langues" do
      post map_features_path, headers: turbo, params: {
        map_feature: { map_layer_id: layer.id, feature_kind: "zone", geometry: polygon.to_json, access: "private",
                       name: "Jardin des familles", name_en: "Families' garden", name_nl: "Tuin van de families",
                       description: "Espace privé", description_en: "Private area", description_nl: "" }
      }

      feature = MapFeature.last
      expect(feature.access).to eq("private")
      expect(feature.name_i18n).to eq("fr" => "Jardin des familles", "en" => "Families' garden", "nl" => "Tuin van de families")
      expect(feature.description(:nl)).to eq("Espace privé")
      expect(feature.missing_translations).to eq(%w[nl])
    end

    it "crée un point utile avec son icône" do
      post map_features_path, headers: turbo, params: {
        map_feature: { map_layer_id: layer.id, feature_kind: "point", geometry: point.to_json, icon: "parking", name: "Parking" }
      }

      expect(MapFeature.last.icon).to eq("parking")
    end

    it "traduit sans toucher au français, et retire l'icône quand on la vide" do
      feature = layer.map_features.create!(feature_kind: "point", geometry: point, name_i18n: { "fr" => "Four à pain" },
                                           properties: { "icon" => "oven" })

      patch map_feature_path(feature), headers: turbo, params: { map_feature: { name_nl: "Broodoven", icon: "" } }

      feature.reload
      expect(feature.name_i18n).to eq("fr" => "Four à pain", "nl" => "Broodoven")
      expect(feature.properties).not_to have_key("icon")
    end

    it "refuse un objet d'accueil sans nom français" do
      expect {
        post map_features_path, headers: turbo, params: {
          map_feature: { map_layer_id: layer.id, feature_kind: "zone", geometry: polygon.to_json, name: "", name_en: "Meadow" }
        }
      }.not_to change(MapFeature, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("doit avoir un nom en français")
    end

    it "signale discrètement les traductions manquantes" do
      feature = layer.map_features.create!(feature_kind: "zone", geometry: polygon, name_i18n: { "fr" => "Le pré" })

      get map_feature_path(feature)

      expect(response.body).to include('data-missing-translations="en nl"', "EN · NL à traduire")
    end
  end
end
