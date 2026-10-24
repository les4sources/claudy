require "rails_helper"

# Projets dans la nouvelle interface (Michael 2026-10-24, « s'inspirer de
# Basecamp ») : cartes par pôle, page du projet en listes à cocher, fiche d'une
# action avec sa discussion. L'ancienne interface garde ses vues.
RSpec.describe "Projets façon Basecamp", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:human) { Human.create!(name: "Malau Hulet", email: "malau@les4sources.be") }
  let(:olivier) { Human.create!(name: "Olivier", email: "olivier@les4sources.be") }
  let(:user) { User.create!(email: "projets-v2@les4sources.be", password: "password123", human_id: human.id, new_interface: true) }
  let(:team) { Team.create!(name: "Pôle Technique") }
  let(:project) do
    Project.create!(name: "Rénovation de la Glycine", team: team, human: olivier, due_date: Date.current + 30,
                    description: "Remettre la Glycine en état pour l’hiver.")
  end
  let(:bundle) { Bundle.create!(project: project, name: "Préparer le chantier", position: 1) }

  def task(name, status: nil, due: nil, humans: [])
    Task.create!(bundle: bundle, project: project, name: name, status: status, due_date: due).tap { |t| t.humans = humans }
  end

  before { sign_in user }

  it "range les projets en cartes par pôle, avec leur avancement et les actions de la personne" do
    task("Demander les devis", status: "closed")
    task("Prévenir les voisins", due: Date.current - 2, humans: [human])
    Project.create!(name: "Four à pain", team: team, human: olivier, status: "done")

    get "/projects"

    body = response.body
    expect(response).to have_http_status(:ok)
    expect(body).to include("ui-pcard")
    expect(body).to include("Rénovation de la Glycine")
    expect(body).to include("Remettre la Glycine en état")
    expect(body).to include("<b>1</b> / 2 actions faites")
    expect(body).to include("1 en retard")
    expect(body).to include("1 projet avance")
    expect(body).to include("Tes actions")
    expect(body).to include("Prévenir les voisins")
    expect(body).not_to include("Four à pain")

    get "/projects", params: { vue: "done" }
    expect(response.body).to include("Four à pain")
    expect(response.body).not_to include(%(href="/projects/#{project.id}"))
  end

  it "montre le projet en listes à cocher, faites repliées, avec sa discussion" do
    task("Demander les devis", status: "closed")
    task("Louer l’échafaudage", status: "in_progress", humans: [olivier])
    task("Annulée", status: "canceled")

    get "/projects/#{project.id}"

    body = response.body
    expect(body).to include("Préparer le chantier")
    expect(body).to include("1/2")
    expect(body).to include("Louer l’échafaudage")
    expect(body).to include("1 action faite")
    expect(body).not_to include("Annulée")
    expect(body).to include("Porté par Olivier")
    expect(body).to include("Discussion sur le projet")
    expect(body).to include("Ajouter une action")
  end

  it "ajoute une action sur place et la renvoie en Turbo Stream" do
    get "/tasks/new", params: { project_id: project.id, bundle_id: bundle.id }
    expect(response.body).to include("Qu’y a-t-il à faire ?")

    post "/tasks", params: { task: { name: "Réserver la benne", bundle_id: bundle.id, project_id: project.id,
                                     human_ids: [olivier.id.to_s], due_date: Date.current + 3 } },
                   as: :turbo_stream

    created = Task.find_by!(name: "Réserver la benne")
    expect(created.humans).to eq([olivier])
    expect(response.body).to include("ui-todo")
    expect(response.body).to include("bundle_#{bundle.id}_tasks")
  end

  it "accepte le même nom d'action dans deux groupes différents" do
    task("Commander le bois")
    other = Bundle.create!(project: project, name: "Le chantier")

    expect(Task.new(bundle: other, project: project, name: "Commander le bois")).to be_valid
    expect(Task.new(bundle: bundle, project: project, name: "Commander le bois")).not_to be_valid
  end

  it "ouvre la fiche d'une action avec la discussion, et cocher depuis la fiche y revient" do
    item = task("Prévenir les voisins", humans: [human])

    get "/tasks/#{item.id}"
    expect(response.body).to include("Confiée à")
    expect(response.body).to include("Discussion sur l’action")

    patch "/tasks/#{item.id}.html", params: { task: { status: "closed" } }
    expect(response).to redirect_to("/tasks/#{item.id}")
    expect(item.reload.status).to eq("closed")
  end

  it "prévient qui porte le projet d'un commentaire sur une action" do
    item = task("Prévenir les voisins", humans: [human])
    olivier_user = User.create!(email: "olivier@les4sources.be", password: "password123", human_id: olivier.id)

    expect(item.comment_recipients).to contain_exactly(user, olivier_user)
    expect(project.comment_recipients).to eq([olivier_user])
  end

  it "garde l'ancienne page pour qui n'a pas basculé" do
    user.update!(new_interface: false)

    get "/projects/#{project.id}"

    expect(response.body).not_to include("ui-todo")
    expect(response.body).to include("project_bundles")
  end
end
