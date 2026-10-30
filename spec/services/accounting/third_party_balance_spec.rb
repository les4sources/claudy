require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La balance des tiers (2026-10-30) : le solde de chaque fournisseur ou client
# à une date, avec la même convention d'ouverture que tous les soldes.
RSpec.describe Accounting::ThirdPartyBalance do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:bank) { build_general_account(code: "550000", name: "Banque") }
  let!(:suppliers) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:customers) { build_general_account(code: "400000", name: "Clients", klass: 4, nature: "asset") }
  let!(:expense) { build_general_account(code: "610000", name: "Loyers", klass: 6, nature: "expense") }
  let!(:revenue) { build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue") }
  let(:proximus) { ThirdParty.create!(name: "Proximus", kind: "supplier") }
  let(:vivaqua) { ThirdParty.create!(name: "Vivaqua", kind: "supplier") }

  def post(lines, date: Date.new(2026, 6, 15), journal: "purchases")
    Accounting::PostDocument.new(legal_entity: entity, journal: journal, entry_date: date,
                                 label: "Test", lines: lines).run!
  end

  def invoice(third_party, cents, date: Date.new(2026, 6, 15))
    post([{ account: expense, debit_cents: cents },
          { account: suppliers, credit_cents: cents, third_party: third_party }], date: date)
  end

  def payment(third_party, cents, date: Date.new(2026, 7, 1))
    post([{ account: suppliers, debit_cents: cents, third_party: third_party },
          { account: bank, credit_cents: cents }], date: date, journal: "bank")
  end

  def balance(side: "suppliers", as_of: Date.new(2026, 12, 31))
    described_class.new(side: side, as_of: as_of, entities: [entity])
  end

  it "donne ce qu'on doit à chaque fournisseur, la plus grosse dette d'abord" do
    invoice(proximus, 30_000)
    payment(proximus, 10_000)
    invoice(vivaqua, 50_000)

    rows = balance.open_rows
    expect(rows.map(&:name)).to eq(%w[Vivaqua Proximus])
    expect(rows.last).to have_attributes(debit_cents: 10_000, credit_cents: 30_000, due_cents: 20_000)
    expect(balance.owed_cents).to eq(70_000)
  end

  it "lit le solde au soir de la date choisie" do
    invoice(proximus, 30_000)
    payment(proximus, 30_000, date: Date.new(2026, 7, 1))

    expect(balance(as_of: Date.new(2026, 6, 30)).open_rows.first.due_cents).to eq(30_000)
    expect(balance(as_of: Date.new(2026, 7, 1)).open_rows).to be_empty
    expect(balance(as_of: Date.new(2026, 7, 1)).rows.first).to be_settled
  end

  it "montre un trop-payé comme une avance" do
    invoice(proximus, 10_000)
    payment(proximus, 15_000)

    expect(balance.open_rows.first.due_cents).to eq(-5_000)
    expect(balance.advances_cents).to eq(5_000)
  end

  it "garde en ligne à part ce qui est posé sans tiers" do
    invoice(nil, 4_000)

    expect(balance.unassigned_row).to have_attributes(name: "(sans tiers)", due_cents: 4_000)
  end

  it "part du solde d'avant l'exercice" do
    build_fiscal_year(entity, year: 2025)
    invoice(proximus, 12_000, date: Date.new(2025, 11, 3))
    payment(proximus, 2_000, date: Date.new(2026, 2, 1))

    row = balance.open_rows.first
    expect(row).to have_attributes(opening_due_cents: 12_000, debit_cents: 2_000, credit_cents: 0, due_cents: 10_000)
  end

  it "lit les clients dans les comptes 40" do
    post([{ account: customers, debit_cents: 25_000, third_party: proximus },
          { account: revenue, credit_cents: 25_000 }], journal: "sales")
    invoice(vivaqua, 9_000)

    clients = balance(side: "customers")
    expect(clients.open_rows.map(&:name)).to eq(["Proximus"])
    expect(clients.owed_cents).to eq(25_000)
  end
end
