require "rails_helper"

# Epic #348, phase 7 — les tâches d'une plante : même composant que celles des
# objets de la carte (phase 6), filière `nourricier` par défaut, porteur tiré
# de la route ; le carnet et la vue « ce mois-ci » comptent aussi les plantes.
RSpec.describe "Carte du domaine — tâches d'une plante (epic #348, phase 7)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "agent-taches-plantes@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:plant) { Plant.create!(name: "Pommier du haut", zone: "Verger") }
  let(:placed) { Plant.create!(name: "Poirier Conférence", zone: "Verger").place!(latitude: 50.34, longitude: 4.905) }
  let(:tasks_target) { ActionView::RecordIdentifier.dom_id(plant, :tasks) }

  def section(body = response.body)
    Nokogiri::HTML(body).at_css(%([data-plant-section="tasks"]))
  end

  it "exige une session Devise" do
    post plant_map_tasks_path(plant), headers: turbo, params: { map_task: { label: "Taille", months: ["2"] } }
    expect(MapTask.count).to eq(0)
  end

  context "connecté" do
    before { sign_in user }

    describe "la section Tâches de la fiche plante" do
      it "liste les tâches, propose d'en ajouter (filière nourricier) et mène au carnet" do
        plant.map_tasks.create!(label: "Taille d'hiver", months: [2], frequency: "tous les ans")

        get plant_path(plant)

        node = section
        expect(node["id"]).to eq(tasks_target)
        expect(node.text).to include("Tâches (1)", "Taille d'hiver", "tous les ans", "Nourricier", "Ajouter une tâche")
        expect(node.at_css(%(form[action="#{plant_map_tasks_path(plant)}"]))).to be_present
        expect(node.at_css(%(form[action="#{plant_map_tasks_path(plant)}"] select[name="map_task[sector]"] option[selected]))["value"]).to eq("nourricier")
        expect(node.at_css(%(a[href="#{map_carnet_path(sector: 'nourricier')}"]))).to be_present
      end
    end

    describe "POST /map/plants/:plant_id/tasks" do
      it "crée la tâche sur la plante, filière nourricier par défaut, et remplace la section" do
        post plant_map_tasks_path(plant), headers: turbo, params: {
          map_task: { label: "Paillage", months: ["", "3", "10"], subject_type: "MapFeature", subject_id: 999 }
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(<turbo-stream action="replace" target="#{tasks_target}">))
        task = MapTask.sole
        expect([task.subject, task.sector, task.months, task.created_by]).to eq([plant, "nourricier", [3, 10], user])
        expect(section.text).to include("Paillage", "Tâches (1)")
      end

      it "refuse lisiblement (422) une tâche sans libellé" do
        post plant_map_tasks_path(plant), headers: turbo, params: { map_task: { label: "", months: ["3"] } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(MapTask.count).to eq(0)
        expect(section.at_css(".bg-red-50").text).to match(/Libellé|Label/)
      end

      it "n'ajoute rien à une plante supprimée" do
        plant.soft_delete!(validate: false)
        expect { post plant_map_tasks_path(plant), headers: turbo, params: { map_task: { label: "Taille" } } }
          .to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe "modification et suppression" do
      let!(:task) { plant.map_tasks.create!(label: "Taille", months: [2]) }

      it "modifie la tâche d'une plante et remplace la section de la plante" do
        patch map_task_path(task), headers: turbo, params: { map_task: { label: "Taille douce", months: ["2", "7"] } }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(target="#{tasks_target}"))
        expect(task.reload.slice(:label, :months)).to eq("label" => "Taille douce", "months" => [2, 7])
      end

      it "supprime (soft) la tâche d'une plante" do
        delete map_task_path(task), headers: turbo

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(target="#{tasks_target}"))
        expect(MapTask.count).to eq(0)
        expect(section.text).to include("Tâches (0)")
      end
    end

    describe "le carnet" do
      it "liste les tâches des plantes : vers leur point si placées, sinon vers leur fiche" do
        plant.map_tasks.create!(label: "Taille du pommier", months: [2])
        placed.map_tasks.create!(label: "Taille du poirier", months: [2])

        get map_carnet_path

        expect(response).to have_http_status(:ok)
        page = Nokogiri::HTML(response.body)
        february = page.at_css(%(details[data-month="2"]))
        expect(february.text).to include("Taille du pommier", "Pommier du haut", "Taille du poirier", "Poirier Conférence")
        expect(february.at_css(%(a[href="#{plant_path(plant)}"])).text).to include("Pommier du haut")
        link = february.at_css(%(a[href="#{map_path(feature: placed.map_feature_id)}"]))
        expect(link.text).to include("Poirier Conférence")
        expect(link["data-subject-link"]).to eq(placed.map_feature_id.to_s)
      end

      it "range les tâches des plantes dans la filière nourricier" do
        plant.map_tasks.create!(label: "Taille du pommier", months: [2])

        get map_carnet_path(sector: "terrain")
        expect(response.body).not_to include("Taille du pommier")
        get map_carnet_path(sector: "nourricier")
        expect(response.body).to include("Taille du pommier")
      end

      it "écarte les tâches d'une plante supprimée" do
        plant.map_tasks.create!(label: "Taille du pommier", months: [2])
        plant.soft_delete!(validate: false)

        get map_carnet_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Taille du pommier")
      end
    end

    describe "GET /map/tasks/current.json" do
      it "renvoie le point des plantes placées ayant une tâche du mois, pas les plantes à placer" do
        layer = MapLayer.for_kind(:management)
        zone = layer.map_features.create!(
          feature_kind: "zone", name_i18n: { "fr" => "Prairie" },
          geometry: { "type" => "Polygon", "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
        )
        zone.map_tasks.create!(label: "Fauche", months: [6])
        placed.map_tasks.create!(label: "Éclaircissage", months: [6])
        plant.map_tasks.create!(label: "Paillage", months: [6])
        Plant.create!(name: "Cerisier").place!(latitude: 50.341, longitude: 4.906).map_tasks.create!(label: "Taille", months: [8])

        travel_to(Date.new(2026, 6, 10)) { get map_tasks_current_path(format: :json) }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["feature_ids"]).to contain_exactly(zone.id, placed.map_feature_id)
      end
    end
  end
end
