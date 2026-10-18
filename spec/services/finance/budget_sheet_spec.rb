require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le budget détaillé (étape 4 du redressement, Michael, 2026-10-18) : une
# ligne par pôle et par compte, préremplie avec les 12 derniers mois.
RSpec.describe Finance::BudgetSheet do
  include FinanceBuilders

  let(:today) { Date.new(2026, 10, 18) }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let(:cuisine) { Team.create!(name: "Pôle Cuisine") }
  let(:bank) { build_general_account(code: "550000", name: "Banque") }
  let(:loyer) { build_general_account(code: "613000", name: "Loyers", klass: 6, nature: "expense") }
  let(:repas) { build_general_account(code: "700100", name: "Repas", klass: 7, nature: "revenue") }

  before do
    build_fiscal_year(entity, year: 2025)
    build_fiscal_year(entity, year: 2026)
  end

  subject(:sheet) { described_class.new(legal_entity: entity, year: 2027, today: today) }

  def post(account, cents, on:, team: nil)
    debit, credit = account.klass == 6 ? [account, bank] : [bank, account]
    Accounting::PostDocument.new(
      legal_entity: entity, journal: "misc", entry_date: on, label: "Test",
      lines: [{ account: debit, debit_cents: cents, team: (team if debit == account) },
              { account: credit, credit_cents: cents, team: (team if credit == account) }]
    ).run!
  end

  it "prend pour référence les douze derniers mois complets" do
    expect(sheet.reference_period).to eq(Date.new(2025, 10, 1)..Date.new(2026, 9, 30))
    expect(sheet.reference_label).to eq("réel d'octobre 2025 à septembre 2026")
  end

  it "prend l'année d'avant pour budgéter l'année en cours" do
    expect(described_class.new(legal_entity: entity, year: 2026, today: today).reference_label).to eq("réel 2025")
  end

  it "propose en brouillon le réel arrondi à l'euro, pôle par pôle, et « Sans pôle » à la fin" do
    post(loyer, 120_040, on: Date.new(2025, 11, 5), team: cuisine)
    post(loyer, 60_000, on: Date.new(2026, 9, 30), team: cuisine)
    post(repas, 300_000, on: Date.new(2026, 3, 1), team: cuisine)
    post(repas, 50_000, on: Date.new(2026, 4, 1))
    post(loyer, 99_900, on: Date.new(2026, 10, 2), team: cuisine) # hors période

    expect(sheet).to be_draft
    expect(sheet.groups.map(&:name)).to eq(["Pôle Cuisine", "Sans pôle"])
    cuisine_rows = sheet.groups.first.rows.to_h { |row| [row.account.code, [row.reference_cents, row.budget_cents]] }
    expect(cuisine_rows).to eq("613000" => [180_040, 180_000], "700100" => [300_000, 300_000])
    expect(sheet.budget).to have_attributes(revenue_cents: 350_000, expense_cents: 180_000, net_cents: 170_000)
  end

  it "enregistre les cases, retire une case vidée et refuse tout si une case est illisible" do
    post(loyer, 120_000, on: Date.new(2026, 1, 5), team: cuisine)
    key = described_class.key_for(cuisine.id, loyer.id)
    autre = described_class.key_for(nil, repas.id)

    expect(sheet.save(key => "1 300", autre => "12k")).to eq(["« 12k » n'est pas un montant lisible (exemple : 12 000 ou 1 250,50)."])
    expect(BudgetLine.count).to eq(0)

    expect(sheet.save(key => "1 300", autre => "250,50")).to eq([])
    expect(BudgetLine.pluck(:team_id, :general_account_id, :amount_cents))
      .to contain_exactly([cuisine.id, loyer.id, 130_000], [nil, repas.id, 25_050])
    expect(sheet).not_to be_draft

    sheet.save(autre => "")
    expect(BudgetLine.where(team_id: nil)).to be_empty
    expect(sheet.groups.first.rows.first.budget_cents).to eq(130_000)
  end

  it "refuse un compte qui n'est ni une charge ni un produit" do
    expect(sheet.save(described_class.key_for(nil, bank.id) => "100").first).to include("classe 6")
    expect(BudgetLine.count).to eq(0)
  end
end
