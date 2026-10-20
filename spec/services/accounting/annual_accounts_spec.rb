require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le bilan et le compte de résultats au schéma abrégé de la BNB (revue
# expert-comptable du 2026-10-20).
RSpec.describe Accounting::AnnualAccounts do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:year_2025) { build_fiscal_year(entity, year: 2025) }
  let(:bank) { build_general_account(code: "550000", name: "Banque") }
  let(:furniture) { build_general_account(code: "240000", name: "Mobilier", klass: 2) }
  let(:depreciation) { build_general_account(code: "240001", name: "Amortissements mobilier", klass: 2) }
  let(:suppliers) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let(:loans) { build_general_account(code: "174001", name: "Certificats", klass: 1, nature: "liability") }
  let(:grants) { build_general_account(code: "733000", name: "Subsides", klass: 7, nature: "revenue") }
  let(:rooms) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }
  let(:rent) { build_general_account(code: "610100", name: "Loyers", klass: 6, nature: "expense") }
  let(:dotation) { build_general_account(code: "630100", name: "Dotations", klass: 6, nature: "expense") }

  def post(debit, credit, cents, date: Date.new(2025, 6, 1))
    post_simple_entry(entity: entity, debit_account: debit, credit_account: credit, amount_cents: cents, entry_date: date)
  end

  def row(rows, code) = rows.find { |r| r.code == code }

  before do
    post(bank, loans, 500_000)
    post(furniture, bank, 120_000)
    post(bank, grants, 80_000)
    post(bank, rooms, 40_000)
    post(rent, suppliers, 30_000)
    post(suppliers, bank, 50_000) # un fournisseur payé deux fois : il devient débiteur
    post(dotation, depreciation, 24_000)
  end

  subject(:accounts) { described_class.new(year_2025) }

  it "range les comptes dans les rubriques et fait balancer le bilan" do
    expect(row(accounts.assets, "24").amount_cents).to eq(96_000)
    expect(row(accounts.assets, "22/27").amount_cents).to eq(96_000)
    expect(row(accounts.assets, "21/28").amount_cents).to eq(96_000)
    expect(row(accounts.assets, "54/58").amount_cents).to eq(450_000)
    # Le 440000 débiteur passe à l'actif, en « autres créances ».
    expect(row(accounts.assets, "41").amount_cents).to eq(20_000)
    expect(row(accounts.liabilities, "17").amount_cents).to eq(500_000)
    expect(row(accounts.liabilities, "44").amount_cents).to eq(0)

    expect(accounts.total_assets_cents).to eq(566_000)
    expect(accounts).to be_balanced
    expect(accounts.warnings.join).to include("provisoires")
  end

  it "calcule le compte de résultats, marge brute comprise" do
    statement = accounts.income_statement
    expect(row(statement, "73").amount_cents).to eq(80_000)
    expect(row(statement, "61").amount_cents).to eq(30_000)
    expect(row(statement, "9900").amount_cents).to eq(90_000)
    expect(row(statement, "630").amount_cents).to eq(24_000)
    expect(row(statement, "9901").amount_cents).to eq(66_000)
    expect(row(statement, "9904").amount_cents).to eq(66_000)
    expect(row(accounts.liabilities, "").amount_cents).to eq(66_000)
  end

  it "après la clôture, montre le résultat dans le résultat reporté et non plus à part" do
    Accounting::CloseFiscalYear.new(fiscal_year: year_2025).run!
    closed = described_class.new(year_2025.reload)

    expect(row(closed.income_statement, "9904").amount_cents).to eq(66_000)
    expect(row(closed.liabilities, "14").amount_cents).to eq(66_000)
    expect(closed.liabilities.select { |r| r.key == :current_result }.sum(&:amount_cents)).to eq(0)
    expect(closed).to be_balanced
    expect(closed.appropriation.map(&:amount_cents)).to eq([66_000, 0, 66_000])

    year_2026 = entity.fiscal_years.find_by(starts_on: Date.new(2026, 1, 1))
    next_year = described_class.new(year_2026)
    expect(row(next_year.liabilities, "14").amount_cents).to eq(66_000)
    expect(row(next_year.liabilities, "14").previous_cents).to eq(66_000)
    expect(next_year.total_assets_cents).to eq(566_000)
    expect(next_year).to be_balanced
  end

  it "montre à part les résultats d'exercices antérieurs pas clôturés" do
    year_2026 = build_fiscal_year(entity, year: 2026)
    entity.fiscal_years.reset
    post(bank, rooms, 5_000, date: Date.new(2026, 2, 1))

    next_year = described_class.new(year_2026)
    expect(next_year.liabilities.find { |r| r.key == :prior_unappropriated }.amount_cents).to eq(66_000)
    expect(next_year).to be_balanced
    expect(next_year.warnings.join).to include("exercices antérieurs ne sont pas clôturés")
  end
end
