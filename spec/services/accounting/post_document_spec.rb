require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le service est le SEUL chemin de création d'une écriture. Ce qu'on teste ici
# n'est pas du confort : c'est la promesse « la double écriture se génère, elle
# ne se saisit jamais », et l'idempotence sans laquelle un import rejoué
# doublerait la comptabilité.
RSpec.describe Accounting::PostDocument do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank) { build_general_account(code: "550000", name: "Banque") }
  let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }
  let(:household) { Household.create!(name: "Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }

  it "produit les deux côtés depuis un seul fait métier" do
    entry = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue,
                              amount_cents: 30_000)

    expect(entry.journal_lines.count).to eq(2)
    expect(entry.debit_cents).to eq(30_000)
    expect(entry.credit_cents).to eq(30_000)
    expect(entry.fiscal_year).to eq(fiscal_year)
  end

  it "accepte un compte désigné par son code" do
    bank
    revenue
    entry = post_simple_entry(entity: entity, debit_account: "550000", credit_account: "700000")

    expect(entry.journal_lines.map { |l| l.general_account.code }).to contain_exactly("550000", "700000")
  end

  it "numérote sans trou par journal et par exercice" do
    first = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)
    second = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)
    autre_journal = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue,
                                      journal: "bank")

    expect([first.number, second.number]).to eq([1, 2])
    expect(autre_journal.number).to eq(1)
  end

  # Repasser le même document ne le comptabilise pas deux fois : c'est ce qui
  # rend un import rejouable sans peur.
  it "est idempotent sur le document source" do
    first = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue,
                              source: household)
    second = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue,
                               source: household)

    expect(second.id).to eq(first.id)
    expect(JournalEntry.count).to eq(1)
  end

  it "sépare les journaux pour un même document" do
    post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue, source: household)
    autre = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue,
                              source: household, journal: "bank")

    expect(JournalEntry.count).to eq(2)
    expect(autre.journal).to eq("bank")
  end

  # Le refus est explicite : ranger l'écriture dans un exercice arbitraire
  # serait pire que de s'arrêter.
  it "refuse de comptabiliser hors de tout exercice" do
    expect {
      post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue,
                        entry_date: Date.new(2019, 3, 1))
    }.to raise_error(described_class::MissingFiscalYear, /exercice/i)
  end

  it "refuse une ventilation déséquilibrée" do
    expect {
      described_class.new(legal_entity: entity, journal: "misc", entry_date: Date.new(2026, 6, 15),
                          label: "Bancale",
                          lines: [{ account: bank, debit_cents: 100 },
                                  { account: revenue, credit_cents: 90 }]).run!
    }.to raise_error(ActiveRecord::RecordInvalid, /déséquilibrée/i)
  end
end
