require "rails_helper"

# Epic #330, phase 4 — l'icône « copier au cycle suivant » sur la page membre.
RSpec.describe "Actions de cycle — copie au cycle suivant (epic #330, phase 4)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "agent-copie@les4sources.be", password: "password123") }
  let(:human) { Human.create!(name: "Chloé", cycle_active: true, roles_enabled: true) }
  let!(:cycle) do
    Cycle.create!(name: "Cycle en cours", start_date: Date.current - 10, end_date: Date.current + 30)
  end
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  def action(**attrs)
    CycleAction.create!({ human: human, cycle: cycle, label: "Action", category: :ponctuelle, hours: 2 }.merge(attrs))
  end

  context "connecté" do
    before { sign_in user }

    context "avec un cycle suivant" do
      let!(:next_cycle) do
        Cycle.create!(name: "Cycle d'après", start_date: Date.current + 31, end_date: Date.current + 60)
      end

      it "copie, puis retire la copie au second clic" do
        a = action

        patch copy_next_cycle_action_path(a), headers: turbo
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("cycle_action_#{a.id}")
        expect(response.body).to include("Copiée dans")
        expect(response.body).to include("Retirer la copie du cycle suivant")
        expect(next_cycle.cycle_actions.where(copied_from_id: a.id).count).to eq(1)
        expect(a.reload.outcome).to be_nil

        patch copy_next_cycle_action_path(a), headers: turbo
        expect(response.body).to include("Copie retirée de")
        expect(response.body).to include("Copier au cycle suivant")
        expect(CycleAction.where(copied_from_id: a.id)).to be_empty
      end

      it "montre l'icône de copie sur la page membre, active quand une copie existe" do
        a = action
        get organisation_member_path(human.id, cycle_id: cycle.id)
        expect(response.body).to include("Copier au cycle suivant (Cycle d&#39;après)")

        CycleActions::CopyService.new(cycle_action: a).run
        get organisation_member_path(human.id, cycle_id: cycle.id)
        expect(response.body).to include("Retirer la copie du cycle suivant")
      end

      it "expose copied_from_id dans l'API" do
        a = action
        CycleActions::CopyService.new(cycle_action: a).run
        copy = a.reload.copy_in_next_cycle
        json = JSON.parse(ApplicationController.render(partial: "api/v1/cycle_actions/cycle_action",
                                                       formats: [:json], locals: { cycle_action: copy }))
        expect(json["copied_from_id"]).to eq(a.id)
      end
    end

    it "sans cycle suivant, renvoie un toast d'erreur et ne crée rien" do
      a = action
      patch copy_next_cycle_action_path(a), headers: turbo
      expect(response.body).to include("Aucun cycle suivant")
      expect(CycleAction.count).to eq(1)
    end
  end

  it "exige l'authentification" do
    a = action
    patch copy_next_cycle_action_path(a)
    expect(response).to redirect_to(new_user_session_path)
    expect(CycleAction.count).to eq(1)
  end
end
