require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# L'acceptation est le SEUL chemin par lequel une proposition devient une
# décision. Tout le reste du rapprochement assisté n'a de valeur que si ce
# passage-là reste un geste humain.
RSpec.describe Finance::AcceptSuggestion do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:energie) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }
  let(:cash_account) { build_cash_account(entity, bank_account) }
  let(:entry) do
    build_cash_entry(cash_account, amount_cents: -12_000, label: "Facture énergie").tap do |e|
      e.update!(counterparty_name: "ENGIE")
    end
  end
  let!(:rule) do
    AllocationRule.create!(label: "Énergie", general_account: energie, legal_entity: entity,
                           team: technique, position: 1, counterparty_name_contains: "ENGIE")
  end
  let(:suggestion) do
    entry # la ligne doit exister avant qu'on demande des suggestions
    Finance::SuggestAllocations.new.run!
    entry.reload.allocation_suggestions.first
  end

  it "crée l'affectation et comptabilise la ligne quand elle est couverte" do
    expect { described_class.new(suggestion: suggestion).run! }.to change { CashAllocation.count }.by(1)

    allocation = entry.reload.cash_allocations.first
    expect(allocation.general_account).to eq(energie)
    expect(allocation.team).to eq(technique)
    expect(allocation.amount_cents).to eq(-12_000)
    expect(entry.status).to eq("allocated")
    expect(entry.posted?).to be(true)
  end

  it "compte l'acceptation sur la règle — c'est ce qui permettra de la juger" do
    expect { described_class.new(suggestion: suggestion).run! }
      .to change { rule.reload.accepted_count }.by(1)
  end

  it "refuse d'accepter deux fois" do
    accepted = suggestion
    described_class.new(suggestion: accepted).run!

    expect {
      described_class.new(suggestion: accepted.reload).run!
    }.to raise_error(described_class::AlreadyDecided)
  end

  it "refuse d'accepter sur une ligne déjà comptabilisée" do
    proposition = suggestion
    allocate(entry, account: energie, amount_cents: -12_000, entity: entity)
    Accounting::PostCashEntry.new(cash_entry: entry.reload).run!

    expect {
      described_class.new(suggestion: proposition.reload).run!
    }.to raise_error(described_class::EntryPosted)
  end
end
