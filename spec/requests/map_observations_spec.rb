require "rails_helper"

# Epic #348, phase 13 — les relevés de biodiversité : création atomique au
# toucher (rien en base avant « Enregistrer »), fiche, autocomplétion des
# espèces déjà saisies, liste filtrée du panneau et compteur d'espèces.
RSpec.describe "Carte du domaine — relevés de biodiversité (epic #348, phase 13)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:alice) { User.create!(email: "alice-bio@les4sources.be", password: "password123") }
  let(:bob) { User.create!(email: "bob-bio@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:layer) { MapLayer.for_kind(:biodiversity) }

  def html(body = response.body) = Nokogiri::HTML(body)

  def observation!(species, realm: "flora", on: "2026-04-12", latin: nil, by: alice)
    layer.map_features.create!(
      feature_kind: "observation", created_by: by,
      geometry: { "type" => "Point", "coordinates" => [4.9078, 50.3414] },
      properties: { "realm" => realm, "species_common" => species, "species_latin" => latin, "observed_on" => on }.compact
    )
  end

  it "exige une session Devise" do
    post map_observations_path, headers: turbo,
                                params: { lat: 50.34, lng: 4.9, observation: { realm: "flora", species_common: "Ail des ours" } }
    expect(MapFeature.observations.count).to eq(0)
    get map_observation_species_path(format: :json, q: "ail")
    expect(response).not_to have_http_status(:ok)
  end

  context "connecté" do
    before { sign_in bob }

    it "crée la couche Biodiversité en ouvrant la carte, avec la liste des relevés" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      expect { get map_path }.to change { MapLayer.where(kind: "biodiversity").count }.from(0).to(1)
      expect(html.at_css(%([data-map-target="layerName"][data-layer-kind="biodiversity"]))).to be_present
      expect(html.at_css("[data-new-observation-url]")["data-new-observation-url"]).to eq(new_map_observation_path)
      expect(html.at_css("turbo-frame#map_observations")["src"]).to eq(map_observations_path)
    end

    it "sert la fiche d'un relevé pas encore créé, sans rien enregistrer" do
      travel_to Time.zone.local(2026, 9, 28, 10) do
        expect { get new_map_observation_path(lat: 50.3414, lng: 4.9078) }.not_to(change { MapFeature.count })
        form = html.at_css("[data-observation-panel] form")
        expect(form["action"]).to eq(map_observations_path)
        expect(form.at_css("input[name=lat]")["value"]).to eq("50.3414")
        expect(form.css("input[name='observation[realm]']").map { |i| i["value"] }).to eq(%w[flora fauna])
        expect(form.at_css("input[name='observation[observed_on]']")["value"]).to eq("2026-09-28")
        expect(form.at_css("select[name='observation[observer_id]'] option[selected]")["value"]).to eq(bob.id.to_s)
      end
    end

    it "crée le point et le relevé ensemble, et ouvre sa fiche" do
      expect do
        post map_observations_path, headers: turbo, params: {
          lat: 50.3414, lng: 4.9078,
          observation: { realm: "fauna", species_common: " Chevreuil ", species_latin: "Capreolus capreolus",
                         observed_on: "2026-09-20", observer_id: alice.id, count: "2", description: "Au bord du ruisseau" }
        }
      end.to change { MapFeature.observations.count }.by(1)

      record = MapFeature.observations.last
      expect(record.map_layer).to eq(layer)
      expect(record.geometry).to eq("type" => "Point", "coordinates" => [4.9078, 50.3414])
      expect(record.created_by).to eq(bob)
      expect(record.observer).to eq(alice)
      expect(record.species_common).to eq("Chevreuil")
      expect(record.observation_count).to eq(2)
      expect(record.description).to eq("Au bord du ruisseau")
      panel = html.at_css("[data-observation-panel]")
      expect(panel["data-feature-saved"]).to eq("true")
      expect(panel["data-feature-id"]).to eq(record.id.to_s)
    end

    it "ne crée rien quand la fiche est incomplète, et la rend avec l'erreur" do
      expect do
        post map_observations_path, headers: turbo,
                                    params: { lat: 50.3414, lng: 4.9078, observation: { realm: "", species_common: "" } }
      end.not_to(change { MapFeature.count })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choisissez Flore ou Faune.")
      expect(html.at_css("[data-observation-panel] input[name=lat]")["value"]).to eq("50.3414")
    end

    it "refuse un point sans coordonnées lisibles" do
      expect do
        post map_observations_path, headers: turbo,
                                    params: { lat: "nord", lng: 4.9, observation: { realm: "flora", species_common: "Ail" } }
      end.not_to(change { MapFeature.count })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "modifie un relevé depuis sa fiche, et l'ouvre au clic sur la carte" do
      record = observation!("Ail des ours")
      get map_feature_path(record)
      expect(html.at_css("[data-observation-panel] form")["action"]).to eq(map_observation_path(record))

      patch map_observation_path(record), headers: turbo,
                                          params: { observation: { realm: "flora", species_common: "Ail des ours", count: "40" } }
      expect(record.reload.observation_count).to eq(40)
      expect(html.at_css("[data-observation-panel]")["data-feature-saved"]).to eq("true")

      patch map_observation_path(record), headers: turbo, params: { observation: { count: "0" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(record.reload.observation_count).to eq(40)
    end

    it "refuse de modifier un objet qui n'est pas un relevé" do
      zone = MapLayer.for_kind(:management).map_features.create!(
        feature_kind: "point", geometry: { "type" => "Point", "coordinates" => [4.9, 50.34] }
      )
      expect { patch map_observation_path(zone), headers: turbo, params: { observation: { species_common: "Ail" } } }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "propose les espèces déjà saisies, avec le latin le plus fréquent" do
      observation!("Ail des ours", latin: "Allium ursinum")
      observation!("ail des ours", latin: "Allium ursinum")
      observation!("Ail des ours", latin: "Allium sp.")
      observation!("Ailante")
      observation!("Aigle royal", realm: "fauna")

      get map_observation_species_path(format: :json, q: "ail", realm: "flora")
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.first).to include("common" => "Ail des ours", "latin" => "Allium ursinum", "count" => 3)
      expect(json.map { |s| s["common"] }).to eq(["Ail des ours", "Ailante"])
    end

    describe "la liste du panneau" do
      before do
        observation!("Ail des ours", on: "2026-04-12")
        observation!("Chevreuil", realm: "fauna", on: "2026-06-01", by: bob)
        observation!("ail des ours", on: "2025-04-02")
        observation!("Hérisson", realm: "fauna", on: "2025-08-15")
      end

      def rows = html.css("[data-observation-row]")

      it "liste les relevés du plus récent au plus ancien, avec le compteur d'espèces" do
        get map_observations_path
        expect(rows.map { |r| r.at_css("[data-observation-species]").text.strip })
          .to eq(["Chevreuil", "Ail des ours", "Hérisson", "ail des ours"])
        expect(html.at_css("[data-species-count]").text).to include("3 espèces distinctes")
        expect(rows.first["data-feature-id"]).to eq(MapFeature.observations.find_by("properties->>'species_common' = 'Chevreuil'").id.to_s)
        expect(rows.first["data-action"]).to include("map#focusObservation")
      end

      it "filtre par règne, espèce et année" do
        get map_observations_path(realm: "fauna")
        expect(rows.size).to eq(2)
        expect(html.at_css("[data-species-count]").text).to include("2 espèces distinctes")

        get map_observations_path(species: "Ail des ours")
        expect(rows.size).to eq(2)
        expect(html.at_css("[data-species-count]").text).to include("1 espèce distincte")

        get map_observations_path(year: "2025", realm: "flora")
        expect(rows.size).to eq(1)
        expect(html.css("select[name=year] option").map { |o| o["value"] }).to eq(["", "2026", "2025"])
      end

      it "a sa page annexe, dont chaque ligne mène au relevé sur la carte" do
        get map_biodiversite_path
        expect(response).to have_http_status(:ok)
        expect(html.at_css("[data-map-subnav]")).to be_present
        expect(html.at_css("[data-observation-row] a")["href"]).to start_with(map_path(feature: ""))
      end
    end
  end
end
