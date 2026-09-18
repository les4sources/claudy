require "rails_helper"

# Epic #330, phase 2 — confronter le pari au réel.
#
# `hours` reste l'ESTIMÉ engagé : c'est lui que le budget du cycle et le bilan
# additionnent. `actual_hours` vit à côté et ne bouge qu'au clic.
RSpec.describe "Actions de cycle — heures réelles (epic #330, phase 2)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "agent-reel@les4sources.be", password: "password123") }
  let(:human) { Human.create!(name: "Chloé", cycle_active: true, roles_enabled: true) }
  let!(:cycle) do
    Cycle.create!(name: "Cycle en cours", start_date: Date.current - 10, end_date: Date.current + 30)
  end

  before { sign_in user }

  def action(**attrs)
    CycleAction.create!({ human: human, cycle: cycle, label: "Action", category: :ponctuelle }.merge(attrs))
  end

  describe "le modèle" do
    it "part à zéro heure réelle" do
      expect(action.actual_hours).to eq(0)
      expect(action).not_to be_actual_hours_recorded
    end

    it "compte les heures une par une et ne descend jamais sous zéro" do
      a = action(hours: 4)
      a.add_actual_hour!
      a.add_actual_hour!
      expect(a.reload.actual_hours).to eq(2)

      a.remove_actual_hour!
      a.remove_actual_hour!
      a.remove_actual_hour!
      expect(a.reload.actual_hours).to eq(0)
    end

    it "ne touche jamais à l'estimé" do
      a = action(hours: 4)
      expect { a.add_actual_hour! }.not_to change { a.reload.hours }
    end
  end

  describe "PATCH add_actual_hour / remove_actual_hour" do
    it "ajoute et retire une heure réelle" do
      a = action(hours: 4)

      patch add_actual_hour_cycle_action_path(a)
      expect(a.reload.actual_hours).to eq(1)

      patch remove_actual_hour_cycle_action_path(a)
      expect(a.reload.actual_hours).to eq(0)
    end

    it "s'arrête à zéro" do
      a = action(hours: 4)
      patch remove_actual_hour_cycle_action_path(a)
      expect(a.reload.actual_hours).to eq(0)
    end

    it "répond en Turbo Stream avec la ligne et le bloc de charge" do
      a = action(hours: 4)
      patch add_actual_hour_cycle_action_path(a), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("cycle_action_#{a.id}")
      expect(response.body).to include("hours_total")
    end

    it "refuse sur un cycle clos" do
      cycle.update!(closed_at: Time.current)
      a = action(hours: 4)
      patch add_actual_hour_cycle_action_path(a)
      expect(a.reload.actual_hours).to eq(0)
    end
  end

  describe "la page membre" do
    it "montre le réel à côté de l'estimé dès qu'une heure est notée" do
      a = action(label: "Tondre", hours: 4)
      a.add_actual_hour!
      a.add_actual_hour!
      a.add_actual_hour!

      get organisation_member_path(human.id, cycle_id: cycle.id)
      expect(response.body).to include("3h réel")
      expect(response.body).to include("4h estimé")
      expect(response.body).to include("Réalisées")
    end

    it "ne montre rien de plus quand aucune heure réelle n'est notée" do
      action(label: "Tondre", hours: 4)
      get organisation_member_path(human.id, cycle_id: cycle.id)

      expect(response.body).to include("4h")
      # Aucun chiffre de réel sur la ligne : l'affichage est celui d'avant.
      expect(response.body).not_to include("h réel")
      expect(response.body).not_to include("h estimé")
    end

    it "nomme le champ du formulaire « Estimé (h) »" do
      get organisation_member_path(human.id, cycle_id: cycle.id)
      expect(response.body).to include("Estimé (h)")
    end

    it "somme les heures réelles des actions vivantes non reportées et non économiques" do
      action(label: "A", hours: 4).add_actual_hour!
      action(label: "B", hours: 2).tap { |a| 2.times { a.add_actual_hour! } }
      action(label: "Reportée", hours: 10, category: :reportee).add_actual_hour!
      action(label: "Éco", hours: 8, economic: true).add_actual_hour!

      get organisation_member_path(human.id, cycle_id: cycle.id)
      # 1 + 2 = 3 h réalisées ; la reportée et l'économique n'y sont pas.
      expect(response.body).to match(/Réalisées.*?>3</m)
    end
  end

  describe "le formulaire" do
    it "ne laisse pas poser les heures réelles" do
      post cycle_actions_path, params: {
        cycle_action: { human_id: human.id, cycle_id: cycle.id, label: "Triche", category: "ponctuelle", hours: "4", actual_hours: "99" }
      }
      expect(CycleAction.last.actual_hours).to eq(0)
    end
  end

  describe "le bilan (décision 3 : inchangé)" do
    it "continue de raisonner sur l'estimé" do
      a = action(label: "Tondre", hours: 4, completed: true)
      5.times { a.add_actual_hour! }

      report = Cycles::MemberReport.new(human: human, cycle: cycle)
      expect(report.planned_hours).to eq(4)
      expect(report.done_hours).to eq(4)
    end
  end
end
