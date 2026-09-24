require "rails_helper"

# Epic #330, phase 5 — lier une action à un pôle.
#
# Le « pôle » d'une action, c'est le modèle `Team` (décision 7). Le lien est
# facultatif et ne sert qu'à afficher : aucune agrégation d'heures par pôle.
RSpec.describe "Actions de cycle — pôle (epic #330, phase 5)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "agent-team@les4sources.be", password: "password123") }
  let(:human) { Human.create!(name: "Chloé", cycle_active: true, roles_enabled: true) }
  let!(:cycle) do
    Cycle.create!(name: "Cycle en cours", start_date: Date.current - 10, end_date: Date.current + 30)
  end
  let!(:cuisine) { Team.create!(name: "Pôle Cuisine", kind: "analytic") }
  let!(:accueil) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before { sign_in user }

  def action(**attrs)
    CycleAction.create!({ human: human, cycle: cycle, label: "Action", category: :ponctuelle }.merge(attrs))
  end

  describe "le modèle" do
    it "n'a pas de pôle par défaut" do
      expect(action.team).to be_nil
    end

    it "retrouve ses actions depuis le pôle" do
      a = action(team: cuisine)
      expect(cuisine.cycle_actions).to contain_exactly(a)
    end
  end

  describe "POST /cycle_actions" do
    def create_action(extra = {})
      post cycle_actions_path, params: {
        cycle_action: { label: "Commander la farine", category: "ponctuelle", unit_hours: 2,
                        human_id: human.id, cycle_id: cycle.id }.merge(extra)
      }, headers: turbo
    end

    it "crée une action liée à un pôle" do
      create_action(team_id: cuisine.id)
      expect(response).to have_http_status(:ok)
      expect(CycleAction.last.team).to eq(cuisine)
    end

    it "crée une action sans pôle quand l'option vide est choisie" do
      create_action(team_id: "")
      expect(response).to have_http_status(:ok)
      expect(CycleAction.last.team).to be_nil
    end
  end

  describe "PATCH /cycle_actions/:id" do
    it "lie, change puis retire le pôle" do
      a = action

      patch cycle_action_path(a), params: { cycle_action: { team_id: cuisine.id } }, headers: turbo
      expect(a.reload.team).to eq(cuisine)

      patch cycle_action_path(a), params: { cycle_action: { team_id: accueil.id } }, headers: turbo
      expect(a.reload.team).to eq(accueil)

      patch cycle_action_path(a), params: { cycle_action: { team_id: "" } }, headers: turbo
      expect(a.reload.team).to be_nil
    end

    it "exige une session" do
      a = action
      sign_out user

      patch cycle_action_path(a), params: { cycle_action: { team_id: cuisine.id } }

      expect(response).to redirect_to(new_user_session_path)
      expect(a.reload.team).to be_nil
    end
  end

  describe "les formulaires" do
    it "proposent le pôle, option vide en premier, groupé par nature" do
      get organisation_member_path(human.id, cycle_id: cycle.id)

      select = Nokogiri::HTML(response.body).at_css("#new_cycle_action_form select[name='cycle_action[team_id]']")
      expect(select).to be_present
      expect(response.body).to include("Pôle (optionnel)")
      expect(select.css("option").first["value"]).to eq("")
      expect(select.css("optgroup").map { |g| g["label"] }).to eq(["Pôle analytique", "Pôle économique"])
    end

    it "préselectionne le pôle à l'édition" do
      a = action(team: accueil)

      get edit_cycle_action_path(a), headers: turbo

      select = Nokogiri::HTML(response.body).at_css("select[name='cycle_action[team_id]']")
      expect(select.at_css("option[selected]")["value"]).to eq(accueil.id.to_s)
    end
  end

  describe "la ligne d'action" do
    it "affiche le badge du pôle quand il y en a un, et rien sinon" do
      action(label: "Liée", team: cuisine)
      action(label: "Libre")

      get organisation_member_path(human.id, cycle_id: cycle.id)

      badges = Nokogiri::HTML(response.body).css(".team-badge")
      expect(badges.map { |b| b.text.strip }).to eq(["Pôle Cuisine"])
    end
  end

  describe "le cycle suivant" do
    let!(:next_cycle) do
      Cycle.create!(name: "Cycle d'après", start_date: cycle.end_date + 1, end_date: cycle.end_date + 60)
    end

    it "la copie reprend le pôle" do
      a = action(team: cuisine)
      patch copy_next_cycle_action_path(a), headers: turbo
      expect(a.reload.copy_in_next_cycle.team).to eq(cuisine)
    end

    it "le report garde le pôle" do
      a = action(team: accueil)
      patch defer_next_cycle_action_path(a), headers: turbo
      expect(a.reload.deferred_to.team).to eq(accueil)
    end
  end

  describe "l'API" do
    def render_json(record)
      JSON.parse(ApplicationController.render(partial: "api/v1/cycle_actions/cycle_action",
                                              formats: [:json], locals: { cycle_action: record }))
    end

    it "expose le pôle (id + nom), ou null" do
      expect(render_json(action(team: cuisine))["team"]).to eq("id" => cuisine.id, "name" => "Pôle Cuisine")
      expect(render_json(action)["team"]).to be_nil
    end
  end
end
