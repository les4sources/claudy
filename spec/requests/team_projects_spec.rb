require "rails_helper"

# Projets rattachés à un pôle (Michael, 2026-10-19) : la page du pôle liste ses
# projets et permet d'en créer un, déjà rattaché.
RSpec.describe "Projets d'un pôle", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:human) { Human.create!(name: "Malau") }
  let(:user) { User.create!(email: "projets-poles@les4sources.be", password: "password123", human: human) }
  let(:team) { Team.create!(name: "Pôle Espaces verts") }
  before { sign_in user }

  it "montre les projets du pôle et leur avancement sur sa page" do
    project = Project.create!(name: "Poulailler mobile", team: team, human: human)
    bundle = project.bundles.create!(name: "Actions du projet", position: 0)
    Task.create!(name: "Plans", project: project, bundle: bundle, status: Task::STATUS_CLOSED)
    Task.create!(name: "Construire", project: project, bundle: bundle)
    Project.create!(name: "Projet d'un autre pôle", team: Team.create!(name: "Pôle Accueil"), human: human)

    get team_path(team)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Poulailler mobile", "action faite sur 2", "Construire")
    expect(response.body).not_to include("Projet d&#39;un autre pôle")
    expect(response.body).to include(new_project_path(team_id: team.id))
  end

  it "préremplit le pôle et le porteur quand on crée un projet depuis le pôle" do
    get new_project_path(team_id: team.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/<option selected="selected" value="#{team.id}">Pôle Espaces verts/)
    expect(response.body).to match(/<option selected="selected" value="#{human.id}">Malau/)
  end

  it "crée le projet dans son pôle" do
    post projects_path, params: { project: { name: "Mare", team_id: team.id, human_id: human.id, status: "active" } }

    project = Project.find_by!(name: "Mare")
    expect(project.team).to eq(team)
    expect(response).to redirect_to(project_path(project))
  end

  it "refuse un projet sans pôle" do
    post projects_path, params: { project: { name: "Orphelin", human_id: human.id } }

    expect(Project.find_by(name: "Orphelin")).to be_nil
  end

  it "range la liste des projets par pôle, les projets sans pôle à la fin" do
    Project.create!(name: "Mare", team: team, human: human)
    sans_pole = Project.new(name: "Ancien projet", human: human)
    sans_pole.save!(validate: false)

    get projects_path

    expect(response.body).to include("Pôle Espaces verts", "Sans pôle")
    expect(response.body.index("Mare")).to be < response.body.index("Ancien projet")
  end
end
