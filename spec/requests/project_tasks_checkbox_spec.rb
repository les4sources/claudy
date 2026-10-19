require "rails_helper"

# Page d'un projet : la case devant chaque action la marque terminée, et ça
# tient au rechargement (la case n'était branchée à rien).
RSpec.describe "Projet — case « action terminée »", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-projets@les4sources.be", password: "password123") }
  let(:project) do
    Project.create!(name: "Rénovation du moulin", team: Team.create!(name: "Pôle Moulin"),
                    human: Human.create!(name: "Porteur du moulin"))
  end
  let(:bundle) { Bundle.create!(name: "Toiture", project: project) }
  let!(:task) { Task.create!(name: "Commander les ardoises", bundle: bundle, project: project, status: Task::STATUS_OPEN) }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before { sign_in user }

  def checkbox_on_project_page
    get project_path(project)
    Nokogiri::HTML(response.body).at_css("#task_#{task.id} input[type=checkbox][name='task[status]']")
  end

  it "affiche une case qui soumet l'action au changement" do
    box = checkbox_on_project_page

    expect(box).to be_present
    expect(box["value"]).to eq(Task::STATUS_CLOSED)
    expect(box["checked"]).to be_nil
    expect(box["onchange"]).to include("requestSubmit")
    form = box.ancestors("form").first
    expect(form["action"]).to eq(task_path(task))
  end

  it "cocher marque l'action terminée, et la case reste cochée au rechargement" do
    patch task_path(task), params: { task: { status: Task::STATUS_CLOSED } }, headers: turbo

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(target="task_#{task.id}"), "line-through")
    expect(task.reload).to be_closed
    expect(checkbox_on_project_page["checked"]).to eq("checked")
  end

  it "décocher la rouvre (le champ caché envoie « open »)" do
    task.update!(status: Task::STATUS_CLOSED)

    patch task_path(task), params: { task: { status: Task::STATUS_OPEN } }, headers: turbo

    expect(task.reload.status).to eq(Task::STATUS_OPEN)
    expect(checkbox_on_project_page["checked"]).to be_nil
  end

  it "garde la redirection classique hors Turbo" do
    patch task_path(task), params: { task: { status: Task::STATUS_CLOSED } }

    expect(response).to redirect_to(task_path(task))
    expect(task.reload).to be_closed
  end
end
