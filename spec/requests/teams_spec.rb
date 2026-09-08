require "rails_helper"

# Epic #239, phase 1 — Paramètres > Pôles : CRUD complet et membres.
RSpec.describe "Paramètres > Pôles", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-poles@les4sources.be", password: "password123") }
  before { sign_in user }

  describe "GET /teams" do
    it "vit dans la sous-navigation Paramètres, plus dans Projets" do
      Team.create!(name: "Accueil")

      get teams_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("subnav-settings")
      expect(response.body).not_to include("subnav-projects")
    end

    it "liste type, code analytique, référent·e·s et nombre de membres" do
      team = Team.create!(name: "Accueil", kind: "economic", analytic_code: "ACC")
      referente = Human.create!(name: "Malau")
      membre = Human.create!(name: "Sébastien")
      TeamMembership.create!(team: team, human: referente, role: "referent")
      TeamMembership.create!(team: team, human: membre, role: "member")

      get teams_path

      expect(response.body).to include("Accueil")
      expect(response.body).to include("Pôle économique")
      expect(response.body).to include("ACC")
      expect(response.body).to include("Malau")
    end

    it "range chaque pôle enfant juste sous son parent" do
      parent = Team.create!(name: "Zèbre")           # dernier par ordre alphabétique
      enfant = Team.create!(name: "Alpaga", parent: parent)
      Team.create!(name: "Bison")

      get teams_path

      corps = response.body
      expect(corps.index("Bison")).to be < corps.index("Zèbre")
      expect(corps.index("Zèbre")).to be < corps.index("Alpaga")
      expect(corps).to include("sous Zèbre")
    end
  end

  describe "le formulaire" do
    it "propose type, parent racine et code analytique" do
      Team.create!(name: "Accueil")

      get new_team_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pôle économique", "Service support")
      expect(response.body).to include("Code analytique")
      expect(response.body).to include("Accueil")
    end

    it "ne se propose jamais lui-même comme parent" do
      team = Team.create!(name: "Accueil")

      get edit_team_path(team)

      options = Nokogiri::HTML(response.body).css("select#team_parent_id option").map { |o| o["value"] }
      expect(options).not_to include(team.id.to_s)
    end

    it "ne propose que des pôles RACINES comme parent" do
      parent = Team.create!(name: "Accueil")
      enfant = Team.create!(name: "Bar", parent: parent)
      team = Team.create!(name: "Cuisine")

      get edit_team_path(team)

      options = Nokogiri::HTML(response.body).css("select#team_parent_id option").map { |o| o["value"] }
      expect(options).to include(parent.id.to_s)
      expect(options).not_to include(enfant.id.to_s)
    end

    it "enregistre type, parent et code analytique" do
      parent = Team.create!(name: "Accueil")

      post teams_path, params: { team: { name: "Bar", kind: "analytic",
                                          parent_id: parent.id, analytic_code: "BAR" } }

      bar = Team.find_by(name: "Bar")
      expect(bar.kind).to eq("analytic")
      expect(bar.parent).to eq(parent)
      expect(bar.analytic_code).to eq("BAR")
    end
  end

  describe "le bloc Membres" do
    let!(:team) { Team.create!(name: "Accueil") }
    let!(:malau) { Human.create!(name: "Malau") }
    let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

    it "apparaît sur l'écran d'édition avec les humains ajoutables" do
      get edit_team_path(team)

      expect(response.body).to include("team-members")
      expect(response.body).to include("Malau")
      expect(response.body).to include("Personne dans ce pôle")
    end

    it "ajoute un membre et renvoie le bloc en Turbo Stream" do
      expect {
        post team_memberships_path(team),
             params: { team_membership: { human_id: malau.id, role: "referent" } }, headers: turbo
      }.to change(TeamMembership, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("team-members")
      expect(team.team_memberships.first.role).to eq("referent")
    end

    it "refuse un humain déjà membre, avec une erreur lisible" do
      TeamMembership.create!(team: team, human: malau, role: "member")

      expect {
        post team_memberships_path(team),
             params: { team_membership: { human_id: malau.id, role: "member" } }, headers: turbo
      }.not_to change(TeamMembership, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Human")
    end

    it "ne propose plus un humain déjà membre" do
      TeamMembership.create!(team: team, human: malau, role: "member")

      get edit_team_path(team)

      options = Nokogiri::HTML(response.body).css("select#team_membership_human_id option").map { |o| o["value"] }
      expect(options).not_to include(malau.id.to_s)
      expect(response.body).to include("Tout le monde est déjà dans ce pôle")
    end

    it "change le rôle d'un membre" do
      membership = TeamMembership.create!(team: team, human: malau, role: "member")

      patch team_membership_path(team, membership),
            params: { team_membership: { role: "referent" } }, headers: turbo

      expect(response).to have_http_status(:ok)
      expect(membership.reload.role).to eq("referent")
    end

    it "retire un membre en douceur — l'historique reste" do
      membership = TeamMembership.create!(team: team, human: malau, role: "member")

      delete team_membership_path(team, membership), headers: turbo

      expect(response).to have_http_status(:ok)
      expect(TeamMembership.count).to eq(0)
      expect(TeamMembership.with_deleted { TeamMembership.count }).to eq(1)
    end

    it "sans Turbo, revient à l'écran d'édition" do
      post team_memberships_path(team), params: { team_membership: { human_id: malau.id, role: "member" } }

      expect(response).to redirect_to(edit_team_path(team))
    end
  end

  it "exige une session" do
    sign_out user

    get teams_path

    expect(response).to redirect_to(new_user_session_path)
  end
end
