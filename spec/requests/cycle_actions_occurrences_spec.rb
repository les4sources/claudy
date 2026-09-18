require "rails_helper"

# Issue #338 — saisir « 11 h × 3 » et cocher les occurrences une par une.
RSpec.describe "Actions de cycle — occurrences (issue #338)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "agent-occurrences@les4sources.be", password: "password123") }
  let(:human) { Human.create!(name: "Stéphanie", cycle_active: true, roles_enabled: true) }
  let!(:cycle) do
    Cycle.create!(name: "Cycle en cours", start_date: Date.current - 10, end_date: Date.current + 30)
  end

  before { sign_in user }

  def build_action(**attrs)
    CycleAction.create!({ human: human, cycle: cycle, label: "Batchcooking", category: :ponctuelle }.merge(attrs))
  end

  describe "la saisie" do
    it "crée une action au total calculé" do
      post cycle_actions_path, params: {
        cycle_action: { human_id: human.id, cycle_id: cycle.id, label: "Batchcooking", category: "ponctuelle", unit_hours: "11", occurrences: "3" }
      }
      action = CycleAction.last
      expect(action.unit_hours).to eq(11)
      expect(action.occurrences).to eq(3)
      expect(action.hours).to eq(33)
    end

    it "recalcule le total à l'édition" do
      action = build_action(unit_hours: 11, occurrences: 3)
      patch cycle_action_path(action), params: { cycle_action: { human_id: human.id, unit_hours: "11", occurrences: "2" } }
      expect(action.reload.hours).to eq(22)
    end
  end

  describe "PATCH complete_occurrence" do
    it "coche une occurrence à la fois et marque l'action faite à la dernière" do
      action = build_action(unit_hours: 11, occurrences: 3)

      patch complete_occurrence_cycle_action_path(action, direction: "up")
      expect(action.reload.completed_occurrences).to eq(1)
      expect(action).not_to be_completed

      patch complete_occurrence_cycle_action_path(action, direction: "up")
      patch complete_occurrence_cycle_action_path(action, direction: "up")
      expect(action.reload.completed_occurrences).to eq(3)
      expect(action).to be_completed
    end

    it "décoche et sort l'action de l'état « faite »" do
      action = build_action(unit_hours: 11, occurrences: 3, completed_occurrences: 3)
      patch complete_occurrence_cycle_action_path(action, direction: "down")
      expect(action.reload.completed_occurrences).to eq(2)
      expect(action).not_to be_completed
    end

    it "ne sort jamais des bornes" do
      action = build_action(unit_hours: 11, occurrences: 2)
      3.times { patch complete_occurrence_cycle_action_path(action, direction: "up") }
      expect(action.reload.completed_occurrences).to eq(2)

      4.times { patch complete_occurrence_cycle_action_path(action, direction: "down") }
      expect(action.reload.completed_occurrences).to eq(0)
    end

    it "répond en Turbo Stream avec la ligne, le total et le compteur" do
      action = build_action(unit_hours: 11, occurrences: 3)
      patch complete_occurrence_cycle_action_path(action, direction: "up"),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("cycle_action_#{action.id}")
      expect(response.body).to include("hours_total")
      expect(response.body).to include("category_ponctuelle_count")
    end
  end

  describe "toggle_completed" do
    it "garde son comportement pour une action « une fois »" do
      action = build_action(hours: 2)
      patch toggle_completed_cycle_action_path(action)
      expect(action.reload).to be_completed
      patch toggle_completed_cycle_action_path(action)
      expect(action.reload).not_to be_completed
    end
  end

  describe "la page membre" do
    it "montre le détail et le total d'une action répétée" do
      build_action(unit_hours: 11, occurrences: 3, completed_occurrences: 2)
      get organisation_member_path(human.id, cycle_id: cycle.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("3 × 11h")
      expect(response.body).to include("33h")
      expect(response.body).to include("2 sur 3 faits")
    end
  end
end
