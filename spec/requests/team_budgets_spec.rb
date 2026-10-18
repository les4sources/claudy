require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le budget annuel d'un pôle (Michael, 2026-10-18), saisi depuis sa page.
RSpec.describe "Organisation — budget d'un pôle", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "budget@les4sources.be", password: "password123") }
  let!(:team) { Team.create!(name: "Pôle Cuisine", kind: "analytic") }

  before { sign_in user }

  it "préremplit un budget neuf avec le réel de l'année d'avant" do
    entity = build_legal_entity
    build_fiscal_year(entity, year: 2025)
    Accounting::PostDocument.new(
      legal_entity: entity, journal: "purchases", entry_date: Date.new(2025, 5, 1), label: "Achat",
      lines: [{ account: build_general_account(code: "600000", klass: 6, nature: "expense"), debit_cents: 123_400, team: team },
              { account: build_general_account(code: "550000"), credit_cents: 123_400 }]
    ).run!

    get edit_team_budget_path(team, 2026)

    body = CGI.unescapeHTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(body).to include("Budget 2026 · Pôle Cuisine", "Prérempli avec le réel 2025")
    expect(body).to include('value="1234"')
  end

  it "enregistre les montants saisis en euros et revient sur les comptes du pôle" do
    patch team_budget_path(team, 2026),
          params: { team_budget: { revenue: "12 000", expense: "8 500,50", notes: "Hypothèse prudente" } }

    budget = team.team_budgets.find_by!(year: 2026)
    expect([budget.revenue_cents, budget.expense_cents, budget.notes]).to eq([1_200_000, 850_050, "Hypothèse prudente"])
    expect(response).to redirect_to(team_path(team, year: 2026))
  end

  it "met à jour le budget existant de l'année au lieu d'en créer un second" do
    TeamBudget.create!(team: team, year: 2026, expense_cents: 100)

    patch team_budget_path(team, 2026), params: { team_budget: { revenue: "0", expense: "500" } }

    expect(team.team_budgets.where(year: 2026).pluck(:expense_cents)).to eq([50_000])
  end

  it "refuse un montant illisible plutôt que de le changer en zéro" do
    patch team_budget_path(team, 2026), params: { team_budget: { revenue: "12k", expense: "100" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(CGI.unescapeHTML(response.body)).to include("n'est pas un montant lisible")
    expect(TeamBudget.count).to eq(0)
  end

  it "reste réservé aux Sourciers" do
    sign_out user
    sign_in User.create!(email: "admin@les4sources.be", password: "password123", access_roles: ["administratif"])

    patch team_budget_path(team, 2026), params: { team_budget: { revenue: "1", expense: "1" } }

    expect(TeamBudget.count).to eq(0)
  end
end
