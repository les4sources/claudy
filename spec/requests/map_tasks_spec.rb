require "rails_helper"

# Epic #348, phase 6 — les tâches de gestion : la section « Tâches » de la
# fiche (CRUD en Turbo Stream), le carnet mois par mois, `/map?feature=<id>`
# et la vue « ce mois-ci ».
RSpec.describe "Carte du domaine — tâches et carnet (epic #348, phase 6)", type: :request do
  include Devise::Test::IntegrationHelpers

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
