require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Annuler une passation ne supprime rien : l'écriture est contre-passée et les
# deux restent au grand livre. Une correction qui efface son erreur oblige à
# croire sur parole.
RSpec.describe Accounting::UnpostCashEntry do
  include FinanceBuilders

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
