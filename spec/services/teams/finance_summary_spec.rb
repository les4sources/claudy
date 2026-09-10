require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #239, phase 3 — ce que le pôle produit et ce qu'il coûte.
RSpec.describe Teams::FinanceSummary do
  include FinanceBuilders

  let(:team) { Team.create!(name: "Pôle Cuisine", kind: "analytic") }
  let(:other_team) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let(:bank) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
  let(:sales) { build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue") }
  let(:supplies) { build_general_account(code: "600000", name: "Achats", klass: 6, nature: "expense") }

  subject(:summary) do
    described_class.new(team: team, from: Date.new(2026, 1, 1), to: Date.new(2026, 12, 31))
  end

  def revenue(amount_cents, on:, for_team: team)
    Accounting::PostDocument.new(
      legal_entity: entity, journal: "sales", entry_date: on, label: "Vente",
      lines: [{ account: bank, debit_cents: amount_cents },
              { account: sales, credit_cents: amount_cents, team: for_team }]
    ).run!
  end

  def expense(amount_cents, on:, for_team: team)
    Accounting::PostDocument.new(
      legal_entity: entity, journal: "purchases", entry_date: on, label: "Achat",
      lines: [{ account: supplies, debit_cents: amount_cents, team: for_team },
              { account: bank, credit_cents: amount_cents }]
    ).run!
  end

  it "somme les produits et les charges du pôle" do
    revenue(120_000, on: Date.new(2026, 3, 1))
    expense(45_000, on: Date.new(2026, 4, 1))

    expect(summary.revenue_cents).to eq(120_000)
    expect(summary.expense_cents).to eq(45_000)
    expect(summary.net_cents).to eq(75_000)
  end

  it "ignore les écritures d'un autre pôle" do
    revenue(120_000, on: Date.new(2026, 3, 1), for_team: other_team)

    expect(summary.revenue_cents).to eq(0)
  end

  it "ignore les écritures hors de la période" do
    build_fiscal_year(entity, year: 2025)
    revenue(90_000, on: Date.new(2025, 6, 1))

    expect(summary.revenue_cents).to eq(0)
  end

  it "ne compte pas les lignes sans pôle — elles restent visibles comme non ventilées" do
    Accounting::PostDocument.new(
      legal_entity: entity, journal: "sales", entry_date: Date.new(2026, 5, 1), label: "Vente sans pôle",
      lines: [{ account: bank, debit_cents: 30_000 }, { account: sales, credit_cents: 30_000 }]
    ).run!

    expect(summary.revenue_cents).to eq(0)
  end

  describe "les affectations de trésorerie" do
    let(:cash_account) { build_cash_account(entity, bank) }

    def allocated(amount_cents, on:, for_team: team)
      entry = build_cash_entry(cash_account, amount_cents: amount_cents, entry_date: on)
      allocate(entry, account: sales, amount_cents: amount_cents, entity: entity, team: for_team)
    end

    it "rend celles du pôle, la plus récente d'abord" do
      old = allocated(10_000, on: Date.new(2026, 2, 1))
      recent = allocated(20_000, on: Date.new(2026, 8, 1))
      allocated(30_000, on: Date.new(2026, 9, 1), for_team: other_team)

      expect(summary.recent_allocations.map(&:id)).to eq([recent.id, old.id])
    end

    it "s'arrête à vingt" do
      25.times { |i| allocated(1_000, on: Date.new(2026, 6, 1) + i.days) }

      expect(summary.recent_allocations.size).to eq(described_class::ALLOCATIONS_LIMIT)
    end
  end

  it "rappelle combien de lignes de trésorerie n'ont été affectées à rien" do
    cash_account = build_cash_account(entity, bank)
    build_cash_entry(cash_account, entry_date: Date.new(2026, 3, 3))
    build_cash_entry(cash_account, entry_date: Date.new(2026, 3, 4))

    expect(summary.unallocated_entries_count).to eq(2)
  end
end
