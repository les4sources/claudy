require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Comptabilité › Budget (étape 4 du redressement, 2026-10-18).
RSpec.describe "Finances > Budget", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-budget@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:cuisine) { Team.create!(name: "Pôle Cuisine") }
  let!(:bank) { build_general_account(code: "550000", name: "Banque") }
  let!(:loyer) { build_general_account(code: "613000", name: "Loyers", klass: 6, nature: "expense") }
  let!(:repas) { build_general_account(code: "700100", name: "Repas", klass: 7, nature: "revenue") }
  let(:year) { Date.current.year + 1 }

  before do
    sign_in user
    build_fiscal_year(entity, year: Date.current.year)
    post_simple_entry(entity: entity, debit_account: loyer, credit_account: bank, amount_cents: 240_000,
                      entry_date: Date.current.beginning_of_month - 10)
  end

  it "ouvre l'an prochain en brouillon, prérempli avec le réel" do
    get finance_budget_path

    corps = CGI.unescapeHTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(corps).to include("Budget #{year}", "Brouillon", "613000", "Sans pôle")
    expect(corps).to include('value="2 400"')
  end

  it "enregistre la feuille et une ligne ajoutée" do
    patch finance_budget_path(entity_id: entity.id, year: year),
          params: { amounts: { "0-#{loyer.id}" => "2 600" },
                    new_line: { team_id: cuisine.id, general_account_id: repas.id, amount: "5 000" } }

    expect(response).to redirect_to(finance_budget_path(entity_id: entity.id, year: year))
    expect(BudgetLine.pluck(:team_id, :general_account_id, :amount_cents))
      .to contain_exactly([nil, loyer.id, 260_000], [cuisine.id, repas.id, 500_000])

    follow_redirect!
    corps = CGI.unescapeHTML(response.body)
    expect(corps).not_to include("Brouillon")
    expect(corps).to include("Pôle Cuisine")
  end

  it "le budget détaillé d'un pôle remplace ses deux montants sur la page du pôle" do
    BudgetLine.create!(year: year, legal_entity: entity, team: cuisine, general_account: repas, amount_cents: 500_000)

    get edit_team_budget_path(cuisine, year)
    expect(response).to redirect_to(team_path(cuisine, year: year))

    accounts = Teams::Accounts.new(team: cuisine, year: year)
    expect(accounts.budget).to have_attributes(revenue_cents: 500_000, expense_cents: 0, detailed: true)
  end
end
