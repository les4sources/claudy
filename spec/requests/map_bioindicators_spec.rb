require "rails_helper"

# La couche « Bio-indicatrices » : relevé photo créé d'un geste (rien en base
# avant « Enregistrer »), statut « À analyser », fiche analysée, liste filtrée,
# et l'analyse écrite par l'API agent.
RSpec.describe "Carte du domaine — plantes bio-indicatrices", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:bob) { User.create!(email: "bob-bioind@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:layer) { MapLayer.for_kind(:bioindicators) }
  let(:photo) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/capture.png"), "image/png") }
  let(:renoncule) do
    BioindicatorSpecies.create!(latin_name: "Ranunculus repens", name: "Renoncule rampante", agronomy: "degrading",
                                indicator_traits: "Sols engorgés l'hiver, tassés.", biotope_primary: "Bords des eaux.",
                                indicators: [{ key: "waterlogging", strength: 3 }])
  end

  def html(body = response.body) = Nokogiri::HTML(body)

  def analyzed!
    layer.map_features.create!(
      feature_kind: "bioindicator", created_by: bob, geometry: { "type" => "Point", "coordinates" => [4.9078, 50.3414] },
      properties: { "status" => "analyzed", "observed_on" => "2026-10-01",
                    "analysis" => { "summary" => "Sol frais, tassé, à engorgement hivernal.", "agronomy" => "degrading",
                                    "indicators" => [{ "key" => "waterlogging", "strength" => 2 }],
                                    "advice" => "Limiter le piétinement en hiver.",
                                    "species" => [{ "species_id" => renoncule.id, "name" => "Renoncule rampante",
                                                    "latin_name" => "Ranunculus repens", "confidence" => "high",
                                                    "abundance" => "frequent", "note" => "Feuilles à segment médian pétiolé." }] } }
    )
  end

  context "connecté" do
    before { sign_in bob }

    it "crée la couche en ouvrant la carte, avec sa fiche de relevé et sa liste" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      expect { get map_path }.to change { MapLayer.where(kind: "bioindicators").count }.from(0).to(1)
      expect(html.at_css(%([data-map-target="layerName"][data-layer-kind="bioindicators"])).text).to include("Bio-indicatrices")
      expect(html.at_css("[data-new-bioindicator-url]")["data-new-bioindicator-url"]).to eq(new_map_bioindicator_path)
      expect(html.at_css("turbo-frame#map_bioindicators")["src"]).to eq(map_bioindicators_path)
    end

    it "sert la fiche d'un relevé pas encore créé : photos (JPEG/PNG, iPhone), date du jour, notes" do
      travel_to Time.zone.local(2026, 10, 2, 10) do
        expect { get new_map_bioindicator_path(lat: 50.3414, lng: 4.9078) }.not_to(change { MapFeature.count })
        form = html.at_css("[data-bioindicator-panel] form")
        expect(form["action"]).to eq(map_bioindicators_path)
        file = form.at_css("input[type=file][name='bioindicator[photos][]']")
        expect(file["accept"]).to eq("image/jpeg,image/png")
        expect(file["multiple"]).to be_present
        expect(file["required"]).to be_present
        # Plusieurs photos prises l'une après l'autre, puis un seul envoi.
        expect(file["data-photo-picker-target"]).to eq("field")
        expect(file["data-direct-upload-url"]).to be_present
        picker = form.at_css(%(input[type=file][data-photo-picker-target="picker"]))
        expect(picker["name"]).to be_nil
        expect(picker["accept"]).to eq("image/jpeg,image/png")
        expect(form.at_css("input[name='bioindicator[observed_on]']")["value"]).to eq("2026-10-02")
        expect(form.at_css("textarea[name='bioindicator[description]']")).to be_present
      end
    end

    it "crée le point avec ses photos et ses notes, « À analyser »" do
      expect do
        post map_bioindicators_path, headers: turbo, params: {
          lat: 50.3414, lng: 4.9078, bioindicator: { description: "Bas de pente, sol piétiné", photos: [photo] }
        }
      end.to change { MapFeature.bioindicators.count }.by(1)

      feature = MapFeature.bioindicators.last
      expect(feature.properties).to include("status" => "to_analyze", "observer_id" => bob.id)
      expect(feature.description_i18n["fr"]).to eq("Bas de pente, sol piétiné")
      expect(feature.photos.size).to eq(1)
      expect(feature.geometry["coordinates"]).to eq([4.9078, 50.3414])
      panel = html.at_css("[data-bioindicator-panel]")
      expect(panel["data-feature-saved"]).to eq("true")
      expect(panel.at_css("[data-bioindicator-status='to_analyze']").text).to include("À analyser")
    end

    it "refuse un relevé sans photo" do
      expect do
        post map_bioindicators_path, headers: turbo, params: { lat: 50.3414, lng: 4.9078, bioindicator: { description: "Rien" } }
      end.not_to(change { MapFeature.count })
      expect(response).to have_http_status(:unprocessable_content)
      expect(html.at_css("[data-bioindicator-errors]").text).to include("Ajoutez au moins une photo")
    end

    it "montre l'analyse : diagnostic, indicateurs, pistes, espèces et leur fiche" do
      feature = analyzed!
      get map_feature_path(feature)

      panel = html.at_css("[data-bioindicator-panel]")
      expect(panel.at_css("[data-bioindicator-status='analyzed']").text).to include("Sol en cours de dégradation")
      analysis = panel.at_css("[data-bioindicator-analysis]")
      expect(analysis.text).to include("Sol frais, tassé, à engorgement hivernal.", "Limiter le piétinement en hiver.")
      expect(analysis.at_css("[data-indicator='waterlogging']").text).to include("Engorgement, hydromorphie")
      species = analysis.at_css("[data-bioindicator-species]")
      expect(species.text).to include("Renoncule rampante", "Ranunculus repens", "Fréquente", "identification sûre")
      expect(species.at_css("[data-bioindicator-sheet='#{renoncule.id}']").text).to include("Sols engorgés l'hiver", "Bords des eaux.")
    end

    it "redemande une analyse" do
      feature = analyzed!
      post request_analysis_map_bioindicator_path(feature), headers: turbo

      expect(feature.reload.bioindicator_status).to eq("to_analyze")
      expect(html.at_css("[data-bioindicator-status='to_analyze']").text).to include("nouvelle analyse demandée")
    end

    it "filtre la liste par statut et par indicateur" do
      analyzed!
      layer.map_features.create!(feature_kind: "bioindicator", created_by: bob,
                                 geometry: { "type" => "Point", "coordinates" => [4.908, 50.341] })

      get map_bioindicators_path
      expect(html.css("[data-bioindicator-row]").size).to eq(2)
      expect(html.text).to include("2 relevés", "1 à analyser")

      get map_bioindicators_path(indicator: "waterlogging")
      rows = html.css("[data-bioindicator-row]")
      expect(rows.size).to eq(1)
      expect(rows.first.text).to include("Renoncule rampante", "Engorgement, hydromorphie")

      get map_bioindicators_path(status: "to_analyze")
      rows = html.css("[data-bioindicator-row]")
      expect(rows.size).to eq(1)
      # La carte ne montre que les relevés retenus par le filtre.
      expect(JSON.parse(html.at_css("[data-bioindicator-list]")["data-filter-ids"])).to eq([rows.first["data-feature-id"].to_i])

      get map_bioindicators_path
      expect(html.at_css("[data-bioindicator-list]")["data-filter-ids"]).to be_nil
    end
  end

  describe "par l'API agent" do
    let(:token) { "test-token-bioind" }
    let(:auth) { { "Authorization" => "Bearer #{token}" } }

    around do |example|
      previous = ENV["AGENT_API_TOKEN"]
      ENV["AGENT_API_TOKEN"] = token
      example.run
      ENV["AGENT_API_TOKEN"] = previous
    end

    it "crée ou complète une fiche espèce (upsert sur le nom latin)" do
      body = { bioindicator_species: { latin_name: "Plantago lanceolata", name: "Plantain lancéolé", agronomy: "balanced",
                                       indicators: [{ key: "biological_activity", strength: 2 }] } }
      post "/api/v1/bioindicator_species", params: body, headers: auth, as: :json
      expect(response).to have_http_status(:created)
      id = JSON.parse(response.body).dig("data", "id")

      post "/api/v1/bioindicator_species", params: { bioindicator_species: { latin_name: "plantago LANCEOLATA", ecology: "preserved" } },
                                           headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data).to include("id" => id, "name" => "Plantain lancéolé", "ecology" => "preserved",
                              "indicators" => [{ "key" => "biological_activity", "strength" => 2 }])

      get "/api/v1/bioindicator_species", params: { latin_name: "Plantago lanceolata" }, headers: auth
      expect(JSON.parse(response.body)["data"].map { |sheet| sheet["id"] }).to eq([id])
    end

    it "liste les relevés à analyser avec leurs photos, puis y écrit l'analyse" do
      feature = layer.map_features.create!(feature_kind: "bioindicator", geometry: { "type" => "Point", "coordinates" => [4.9078, 50.3414] })
      feature.photos.attach(photo)

      get "/api/v1/map_features", params: { layer_kind: "bioindicators", kind: "bioindicator" }, headers: auth
      listed = JSON.parse(response.body)["data"].first
      expect(listed["properties"]).to include("status" => "to_analyze")

      get "/api/v1/map_features/#{feature.id}", headers: auth
      expect(JSON.parse(response.body).dig("data", "photos").first["url"]).to be_present

      properties = listed["properties"].merge(
        "status" => "analyzed",
        "analysis" => { "summary" => "Sol frais, tassé.", "agronomy" => "degrading",
                        "indicators" => [{ "key" => "compaction", "strength" => 2 }],
                        "species" => [{ "species_id" => renoncule.id, "name" => "Renoncule rampante", "confidence" => "high" }] }
      )
      patch "/api/v1/map_features/#{feature.id}", params: { map_feature: { properties: properties } }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(feature.reload.analysis_agronomy).to eq("degrading")
      expect(feature.bioindicator_status).to eq("analyzed")

      patch "/api/v1/map_features/#{feature.id}", params: { map_feature: { properties: properties.merge("analysis" => { "summary" => "" }) } },
                                                  headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
