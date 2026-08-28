require "rails_helper"

# Épic cycles — bilan, page membre par cycle, clôture.
RSpec.describe "Cycles — bilan et clôture", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-cycles@les4sources.be", password: "password123") }
  let(:human) { Human.create!(name: "Chloé", cycle_active: true, roles_enabled: true) }
  let!(:cycle) { Cycle.create!(name: "Cycle printemps", start_date: Date.current - 60, end_date: Date.current - 10) }
  let!(:next_cycle) { Cycle.create!(name: "Cycle été", start_date: Date.current + 5, end_date: Date.current + 60) }

  before { sign_in user }

  it "GET /cycles/:id montre le bilan par membre" do
    CycleAction.create!(human: human, cycle: cycle, label: "Tondre", hours: 2, category: :ponctuelle, completed: true)
    CycleAction.create!(human: human, cycle: cycle, label: "Peindre", hours: 4, category: :ponctuelle, outcome: :deferred)
    get cycle_path(cycle)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Cycle printemps")
    expect(response.body).to include("Chloé")
    expect(response.body).to include("Tondre")
    expect(response.body).to include("Peindre")
    expect(response.body).to include("Clôturer ce cycle")
  end

  it "la page membre est scopée au cycle demandé" do
    CycleAction.create!(human: human, cycle: cycle, label: "Action ancienne", category: :ponctuelle)
    CycleAction.create!(human: human, cycle: next_cycle, label: "Action future", category: :ponctuelle)

    get organisation_member_path(human.id, cycle_id: cycle.id)
    expect(response.body).to include("Action ancienne")
    expect(response.body).not_to include("Action future")

    get organisation_member_path(human.id, cycle_id: next_cycle.id)
    expect(response.body).to include("Action future")
    expect(response.body).not_to include("Action ancienne")
  end

  it "sans paramètre, la page membre ouvre le dernier cycle passé encore ouvert" do
    get organisation_member_path(human.id)
    expect(response.body).to include("Cycle printemps")
    expect(response.body).to include("Terminé, à clôturer")
  end

  it "la création d'une action tombe dans le cycle affiché" do
    post cycle_actions_path, params: { cycle_action: { human_id: human.id, cycle_id: next_cycle.id, label: "Nouvelle", category: "ponctuelle" } }
    expect(CycleAction.last.cycle).to eq(next_cycle)
  end

  it "PATCH defer_next crée la copie et l'annulation la retire" do
    action = CycleAction.create!(human: human, cycle: cycle, label: "À passer", category: :ponctuelle)
    patch defer_next_cycle_action_path(action)
    expect(response).to redirect_to(organisation_member_path(human.id, cycle_id: cycle.id))
    expect(action.reload).to be_outcome_deferred
    expect(next_cycle.cycle_actions.count).to eq(1)

    patch undo_defer_next_cycle_action_path(action)
    expect(action.reload.outcome).to be_nil
    expect(next_cycle.cycle_actions.count).to eq(0)
  end

  it "PATCH defer_next sans cycle suivant renvoie l'alerte" do
    next_cycle.soft_delete!(validate: false)
    action = CycleAction.create!(human: human, cycle: cycle, label: "Bloquée", category: :ponctuelle)
    patch defer_next_cycle_action_path(action)
    follow_redirect!
    expect(response.body).to include("Aucun cycle suivant")
    expect(action.reload.outcome).to be_nil
  end

  it "archiver une action non cochée la marque abandonnée" do
    action = CycleAction.create!(human: human, cycle: cycle, label: "Laissée", category: :ponctuelle)
    patch archive_cycle_action_path(action)
    expect(action.reload).to be_archived
    expect(action).to be_outcome_dropped
  end

  it "GET /cycles/:id/closing puis POST close ferme le cycle" do
    CycleAction.create!(human: human, cycle: cycle, label: "Rituel", category: :rituelle)
    get closing_cycle_path(cycle)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Le moment de finalisation")
    expect(response.body).to include("Rituel")

    post close_cycle_path(cycle)
    expect(response).to redirect_to(cycle_path(cycle))
    expect(cycle.reload).to be_closed
    expect(next_cycle.cycle_actions.where(label: "Rituel").count).to eq(1)
  end

  it "un cycle clos refuse les mutations et s'affiche en lecture seule" do
    action = CycleAction.create!(human: human, cycle: cycle, label: "Figée", category: :ponctuelle)
    cycle.update!(closed_at: Time.current)

    get organisation_member_path(human.id, cycle_id: cycle.id)
    expect(response.body).to include("Ce cycle est clos")
    expect(response.body).not_to include("new_cycle_action_form")

    patch toggle_completed_cycle_action_path(action)
    expect(action.reload).not_to be_completed

    post cycle_actions_path, params: { cycle_action: { human_id: human.id, cycle_id: cycle.id, label: "Refusée", category: "ponctuelle" } }
    expect(CycleAction.where(label: "Refusée")).to be_empty
  end

  it "un cycle qui contient des actions ne se supprime pas" do
    CycleAction.create!(human: human, cycle: cycle, label: "Ancre", category: :ponctuelle)
    delete cycle_path(cycle)
    expect(cycle.reload.deleted_at).to be_nil
    expect(flash[:alert]).to include("contient des actions")
  end

  it "la vue d'ensemble ne compte que le cycle de référence" do
    CycleAction.create!(human: human, cycle: cycle, label: "Comptée", hours: 5, category: :ponctuelle)
    CycleAction.create!(human: human, cycle: next_cycle, label: "Pas comptée", hours: 7, category: :ponctuelle)
    get organisation_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Cycle printemps")
    expect(response.body).to match(/>5<\/span>|>5\.0<|5<\/span>/)
  end
end
