require "rails_helper"

# Epic #330, phase 6 — les icônes de la ligne d'action portent une bulle
# stylisée (contrôleur Stimulus `tooltip`) au lieu du `title=` natif, avec un
# `aria-label` équivalent pour les lecteurs d'écran.
RSpec.describe "Actions de cycle — tooltips stylisés (epic #330, phase 6)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "agent-tooltips@les4sources.be", password: "password123") }
  let(:human) { Human.create!(name: "Chloé", cycle_active: true, roles_enabled: true) }
  let!(:cycle) do
    Cycle.create!(name: "Cycle en cours", start_date: Date.current - 10, end_date: Date.current + 30)
  end

  before { sign_in user }

  def action(**attrs)
    CycleAction.create!({ human: human, cycle: cycle, label: "Action", category: :ponctuelle, hours: 2 }.merge(attrs))
  end

  def row_controls(cycle_action)
    get organisation_member_path(human.id, cycle_id: cycle.id)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).css("#cycle_action_#{cycle_action.id} [data-controller~='tooltip']")
  end

  def labels(controls) = controls.map { |c| c["aria-label"] }

  context "avec un cycle suivant" do
    before { Cycle.create!(name: "Cycle d'hiver", start_date: Date.current + 31, end_date: Date.current + 60) }

    it "met une bulle sur chaque icône de droite, « € » et « ± h » compris" do
      ca = action(actual_hours: 1)

      expect(labels(row_controls(ca))).to eq([
        "Retirer une heure réelle",
        "Ajouter une heure réelle",
        "Marquer comme activité économique (hors budget d'heures)",
        "Copier au cycle suivant (Cycle d'hiver)",
        "Passer au cycle suivant (Cycle d'hiver)",
        "Mettre en attente (catégorie reportée)",
        "Modifier",
        "Archiver sans la faire",
        "Supprimer"
      ])
    end

    it "remplace le title natif par un aria-label et le texte de la bulle" do
      row_controls(action).each do |control|
        expect(control["title"]).to be_nil
        expect(control["data-tooltip-text-value"]).to eq(control["aria-label"])
        expect(control["data-action"]).to include("mouseenter->tooltip#show", "focus->tooltip#show")
      end
    end

    it "suit l'état de l'action : économique, copiée, faite" do
      ca = action(economic: true, completed: true)
      CycleActions::CopyService.new(cycle_action: ca).run

      expect(labels(row_controls(ca))).to eq([
        "Ajouter une heure réelle",
        "Retirer le mode activité économique",
        "Retirer la copie du cycle suivant (Cycle d'hiver)",
        "Modifier",
        "Archiver (faite)",
        "Supprimer"
      ])
    end

    it "garde la confirmation de suppression" do
      delete_button = row_controls(action).find { |c| c["aria-label"] == "Supprimer" }
      expect(delete_button["data-turbo-confirm"]).to eq("Supprimer cette action ?")
    end
  end

  it "sans cycle suivant, la bulle invite à créer un cycle" do
    expect(labels(row_controls(action))).to include("Aucun cycle suivant configuré — créer un cycle")
  end
end
