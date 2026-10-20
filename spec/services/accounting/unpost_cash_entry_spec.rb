require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Annuler une passation ne supprime rien : l'écriture est contre-passée et les
# deux restent au grand livre. Une correction qui efface son erreur oblige à
# croire sur parole.
RSpec.describe Accounting::UnpostCashEntry do
  include FinanceBuilders
  include ActiveSupport::Testing::TimeHelpers

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }
  let(:cash_account) { build_cash_account(entity, bank_account) }
  let(:entry) do
    e = build_cash_entry(cash_account, amount_cents: 60_000)
    allocate(e, account: revenue, amount_cents: 60_000, entity: entity)
    e
  end

  it "contre-passe l'écriture et rend la ligne réaffectable" do
    Accounting::PostCashEntry.new(cash_entry: entry).run!

    expect { described_class.new(cash_entry: entry.reload).run! }
      .to change { JournalEntry.count }.by(1)

    expect(entry.reload.status).to eq("pending")
    expect(entry.journal_entry).to be_nil

    lignes = JournalLine.joins(:journal_entry).where(general_account_id: bank_account.id)
    expect(lignes.sum(:debit_cents) - lignes.sum(:credit_cents)).to eq(0)
  end

  it "permet de réaffecter puis de recomptabiliser après annulation" do
    Accounting::PostCashEntry.new(cash_entry: entry).run!
    described_class.new(cash_entry: entry.reload).run!

    entry.cash_allocations.each(&:destroy)
    autre = build_general_account(code: "700100", name: "Salles", klass: 7, nature: "revenue")
    allocate(entry.reload, account: autre, amount_cents: 60_000, entity: entity)

    expect { Accounting::PostCashEntry.new(cash_entry: entry.reload).run! }
      .to change { JournalEntry.count }.by(1)
  end

  # Une ligne d'une année encore ouverte, réaffectée l'année suivante : son
  # annulation doit rester dans son année, là où la nouvelle affectation se
  # comptabilise. Datée du jour, la charge serait comptée deux fois en 2025.
  it "date la contre-passation de l'écriture d'origine, pas du jour" do
    exercice_2025 = build_fiscal_year(entity, year: 2025)
    ancienne = build_cash_entry(cash_account, amount_cents: 60_000, entry_date: Date.new(2025, 6, 15))
    allocate(ancienne, account: revenue, amount_cents: 60_000, entity: entity)
    Accounting::PostCashEntry.new(cash_entry: ancienne).run!

    travel_to(Date.new(2026, 3, 10)) { described_class.new(cash_entry: ancienne.reload).run! }

    miroir = JournalEntry.where.not(reversal_of_id: nil).sole
    expect(miroir.entry_date).to eq(Date.new(2025, 6, 15))
    expect(miroir.fiscal_year).to eq(exercice_2025)

    ancienne.cash_allocations.each(&:destroy)
    autre = build_general_account(code: "700100", name: "Salles", klass: 7, nature: "revenue")
    allocate(ancienne.reload, account: autre, amount_cents: 60_000, entity: entity)
    Accounting::PostCashEntry.new(cash_entry: ancienne.reload).run!

    solde = lambda do |compte, exercice|
      lignes = JournalLine.joins(:journal_entry)
                          .where(general_account_id: compte.id, journal_entries: { fiscal_year_id: exercice.id })
      lignes.sum(:credit_cents) - lignes.sum(:debit_cents)
    end
    expect(solde.call(revenue, exercice_2025)).to eq(0)
    expect(solde.call(autre, exercice_2025)).to eq(60_000)
    expect(JournalEntry.where(fiscal_year: fiscal_year)).to be_empty
  end

  it "refuse d'annuler dans un exercice clôturé" do
    Accounting::PostCashEntry.new(cash_entry: entry).run!
    fiscal_year.close!

    expect {
      described_class.new(cash_entry: entry.reload).run!
    }.to raise_error(described_class::ClosedFiscalYear, /clôturé/i)
  end

  it "refuse d'annuler une ligne non comptabilisée" do
    expect {
      described_class.new(cash_entry: entry).run!
    }.to raise_error(described_class::NotPosted)
  end
end
