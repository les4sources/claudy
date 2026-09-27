require "rails_helper"

# Epic #348, phase 6 — les tâches de gestion : la section « Tâches » de la
# fiche (CRUD en Turbo Stream), le carnet mois par mois, `/map?feature=<id>`
# et la vue « ce mois-ci ».
RSpec.describe "Carte du domaine — tâches et carnet (epic #348, phase 6)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "agent-taches@les4sources.be", password: "password123") }
  let(:layer) { MapLayer.for_kind(:management) }
  let(:polygon) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:feature) { zone }

  def zone(name = "La prairie du bas")
    layer.map_features.create!(feature_kind: "zone", geometry: polygon, name_i18n: { "fr" => name })
  end

  it "exige une session Devise" do
    post map_feature_map_tasks_path(feature), params: { map_task: { label: "Fauche", months: ["6"] } }, headers: turbo
    expect(MapTask.count).to eq(0)
    get map_carnet_path
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  context "connecté" do
    before { sign_in user }

    describe "la section Tâches de la fiche" do
      it "apparaît pour un objet de Gestion enregistré, avec ses tâches et leurs douze pastilles" do
        feature.map_tasks.create!(label: "Fauche des orties", months: [3, 10], frequency: "tous les ans")

        get map_feature_path(feature)

        expect(response.body).to include("Tâches", "Fauche des orties", "tous les ans", "Ajouter une tâche")
        page = Nokogiri::HTML(response.body)
        pills = page.css("[data-task-id] [data-month]")
        expect(pills.size).to eq(12)
        expect(pills.select { |pill| pill["data-active"] == "true" }.map { |pill| pill["data-month"] }).to eq(%w[3 10])
        # La consigne de gestion reste, en texte libre complémentaire.
        expect(response.body).to include("Consigne de gestion")
      end

      it "n'apparaît pas pour un objet pas encore enregistré" do
        get new_map_feature_path(layer_id: layer.id, feature_kind: "zone")
        expect(response.body).not_to include("Ajouter une tâche")
      end

      it "n'apparaît pas hors de la couche Gestion" do
        welcome = MapLayer.for_kind(:welcome).map_features.create!(feature_kind: "zone", geometry: polygon,
                                                                    name_i18n: { "fr" => "Le parking" })
        get map_feature_path(welcome)
        expect(response.body).not_to include("Ajouter une tâche")
      end
    end

    describe "POST /map/features/:id/tasks" do
      it "crée la tâche (filière terrain par défaut) et remplace la section" do
        expect {
          post map_feature_map_tasks_path(feature), headers: turbo, params: {
            map_task: { label: "Fauche des orties", months: ["", "10", "3"], frequency: "annuel", notes: "Laisser un refuge" }
          }
        }.to change(MapTask, :count).by(1)

        task = MapTask.last
        expect(task).to have_attributes(subject: feature, label: "Fauche des orties", months: [3, 10],
                                        sector: "terrain", frequency: "annuel", created_by: user)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include(%(target="tasks_map_feature_#{feature.id}"), "Fauche des orties")
      end

      it "refuse une tâche sans libellé et rouvre le formulaire avec l'erreur" do
        expect {
          post map_feature_map_tasks_path(feature), headers: turbo, params: { map_task: { label: " ", months: ["6"] } }
        }.not_to change(MapTask, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Libellé")
      end

      it "ignore un sujet ou un porteur passé en paramètre" do
        post map_feature_map_tasks_path(feature), headers: turbo, params: {
          map_task: { label: "Taille", months: ["2"], subject_type: "User", subject_id: user.id, sector: "nourricier" }
        }
        expect(MapTask.last).to have_attributes(subject_type: "MapFeature", subject_id: feature.id, sector: "nourricier")
      end
    end

    describe "GET /map/carnet" do
      around { |example| travel_to(Date.new(2026, 3, 15)) { example.run } }

      let!(:fauche) { feature.map_tasks.create!(label: "Fauche des orties", months: [3, 10]) }
      let!(:taille) { zone("Le verger").map_tasks.create!(label: "Taille des pommiers", months: [3], sector: "nourricier") }

      def month_section(page, month) = page.at_css(%(details[data-month="#{month}"]))

      it "range chaque tâche dans chacun de ses mois, avec le nom de l'objet et un lien vers la carte" do
        get map_carnet_path

        expect(response).to have_http_status(:ok)
        page = Nokogiri::HTML(response.body)
        expect(page.css("details[data-month]").map { |d| d["data-month"] }).to eq((1..12).map(&:to_s))
        expect(month_section(page, 3).text).to include("Mars", "Fauche des orties", "Taille des pommiers", "La prairie du bas")
        expect(month_section(page, 10).text).to include("Octobre", "Fauche des orties")
        expect(month_section(page, 10).text).not_to include("Taille des pommiers")
        expect(month_section(page, 3).at_css("[data-task-count]").text.strip).to eq("2")
        expect(month_section(page, 10).at_css("[data-task-count]").text.strip).to eq("1")
        expect(month_section(page, 3).at_css(%(a[href="#{map_path(feature: feature.id)}"]))).to be_present
      end

      it "ouvre le mois courant et replie les autres" do
        get map_carnet_path
        page = Nokogiri::HTML(response.body)
        expect(month_section(page, 3)["open"]).not_to be_nil
        expect(month_section(page, 3)["data-current-month"]).to eq("true")
        expect(month_section(page, 10)["open"]).to be_nil
      end

      it "filtre par filière" do
        get map_carnet_path(sector: "nourricier")
        page = Nokogiri::HTML(response.body)
        expect(month_section(page, 3).text).to include("Taille des pommiers")
        expect(month_section(page, 3).text).not_to include("Fauche des orties")

        get map_carnet_path(sector: "n'importe quoi")
        expect(response.body).to include("Fauche des orties", "Taille des pommiers")
      end

      it "écarte les tâches d'un objet supprimé" do
        feature.soft_delete!(validate: false)
        get map_carnet_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Fauche des orties")
        expect(response.body).to include("Taille des pommiers")
      end

      it "a son entrée dans le panneau de la carte" do
        MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                             bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
        get map_path
        expect(Nokogiri::HTML(response.body).at_css(%(a[data-map-carnet-link][href="#{map_carnet_path}"]))).to be_present
      end
    end

    describe "/map?feature=<id> et la vue « ce mois-ci »" do
      before do
        MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                             bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      end

      def map_root = Nokogiri::HTML(response.body).at_css("[data-controller='map']")

      it "transmet l'objet à montrer à la carte" do
        get map_path(feature: feature.id)
        expect(response).to have_http_status(:ok)
        expect(map_root["data-map-focus-feature-value"]).to eq(feature.id.to_s)
        expect(map_root["data-map-current-tasks-url-value"]).to eq(map_tasks_current_path(format: :json))
      end

      it "ignore sans erreur un id inconnu, supprimé ou illisible" do
        gone = zone("Disparue").tap { |f| f.soft_delete!(validate: false) }
        [gone.id, 999_999, "abc", "1 OR 1=1"].each do |value|
          get map_path(feature: value)
          expect(response).to have_http_status(:ok)
          expect(map_root["data-map-focus-feature-value"]).to be_nil
        end
      end

      it "propose la case « ce mois-ci » dans le panneau" do
        get map_path
        expect(Nokogiri::HTML(response.body).at_css("input[data-map-month-toggle][data-action='change->map#toggleMonthFocus']")).to be_present
      end

      it "liste en JSON les objets porteurs d'une tâche du mois courant, objets supprimés exclus" do
        travel_to(Date.new(2026, 10, 2)) do
          feature.map_tasks.create!(label: "Fauche", months: [3, 10])
          feature.map_tasks.create!(label: "Broyage", months: [10])
          zone("Le verger").map_tasks.create!(label: "Taille", months: [2])
          zone("Disparue").tap { |f| f.map_tasks.create!(label: "Oubliée", months: [10]) }.soft_delete!(validate: false)

          get map_tasks_current_path(format: :json)

          body = JSON.parse(response.body)
          expect(body).to include("month" => 10, "month_name" => "Octobre", "feature_ids" => [feature.id])
        end
      end
    end

    describe "PATCH et DELETE /map/tasks/:id" do
      let!(:task) { feature.map_tasks.create!(label: "Fauche", months: [6]) }

      it "modifie la tâche" do
        patch map_task_path(task), headers: turbo,
                                   params: { map_task: { label: "Fauche tardive", months: ["", "9"], sector: "nourricier" } }
        expect(task.reload).to have_attributes(label: "Fauche tardive", months: [9], sector: "nourricier")
        expect(response.body).to include("Fauche tardive")
      end

      it "refuse un mois hors calendrier" do
        patch map_task_path(task), headers: turbo, params: { map_task: { months: ["13"] } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(task.reload.months).to eq([6])
      end

      it "supprime la tâche (soft-delete)" do
        delete map_task_path(task), headers: turbo
        expect(MapTask.find_by(id: task.id)).to be_nil
        expect(MapTask.unscoped.find(task.id).deleted_at).to be_present
        expect(response.body).not_to include(%(data-task-id="#{task.id}"))
      end

      it "ne trouve plus la tâche d'un objet supprimé (404)" do
        feature.soft_delete!(validate: false)
        expect {
          patch map_task_path(task), headers: turbo, params: { map_task: { label: "Revenante" } }
        }.to raise_error(ActiveRecord::RecordNotFound)
        expect(task.reload.label).to eq("Fauche")
      end
    end
  end
end
