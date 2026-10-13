require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Les prêts reçus (Michael, 2026-10-13) : par prêteur, lus au grand livre.
RSpec.describe Finance::Loans do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:sourciers) { build_general_account(code: "174004", name: "Prêt court terme Sourciers", klass: 1, nature: "liability") }
  let!(:muriel) { build_general_account(code: "174006", name: "Prêt CT Muriel", klass: 1, nature: "liability") }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }
  let(:gaelle) { ThirdParty.create!(code: "DEFAYS", name: "Gaëlle de Fays", kind: "supplier") }

  def mouvement(cents, tiers:, date: Date.new(2026, 6, 10))
    entry = build_cash_entry(compte_bancaire, amount_cents: cents, entry_date: date, label: "Prêt")
    entry.cash_allocations.create!(general_account: sourciers, amount_cents: cents, legal_entity: entity, third_party: tiers)
    Accounting::PostCashEntry.new(cash_entry: entry).run!
  end

  it "dit, par prêteur, ce qui est emprunté, remboursé et encore dû" do
    mouvement(1_000_000, tiers: gaelle)
    mouvement(-200_000, tiers: gaelle, date: Date.new(2026, 9, 9))
    post_simple_entry(entity: entity, debit_account: banque, credit_account: muriel, amount_cents: 500_000)

    groupe = described_class.new.groups.sole
    expect(groupe.entity).to eq(entity)
    expect(groupe.owed_cents).to eq(1_300_000)

    prete = groupe.lenders.first
    expect(prete).to have_attributes(name: "Gaëlle de Fays", borrowed_cents: 1_000_000, repaid_cents: 200_000,
                                     owed_cents: 800_000, last_movement_on: Date.new(2026, 9, 9))
    expect(prete).to be_named
    expect(groupe.lenders.second).to have_attributes(name: "Prêt CT Muriel", owed_cents: 500_000)
    expect(groupe.lenders.second).not_to be_named
  end

  it "oublie un prêt entièrement remboursé" do
    mouvement(1_000_000, tiers: gaelle)
    mouvement(-1_000_000, tiers: gaelle)

    expect(described_class.new).not_to be_any
  end
end
