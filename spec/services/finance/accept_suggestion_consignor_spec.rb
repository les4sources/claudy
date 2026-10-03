require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 4 — accepter une suggestion au compte artisanat dit à quel
# artisan revient le virement. La règle propose ; c'est l'acceptation, un geste
# humain, qui rattache.
RSpec.describe Finance::AcceptSuggestion do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:artisanat) { build_general_account(code: "701005", name: "Artisanat", klass: 7, nature: "revenue") }
  let!(:cellier) { build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue") }
  let!(:emilie) { Consignor.create!(name: "Émilie", settlement_mode: "invoice") }
  let!(:bruno) { Consignor.create!(name: "Bruno", settlement_mode: "invoice") }

  def suggestion_for(communication)
    entry = build_cash_entry(bank, amount_cents: 1_500).tap { |e| e.update!(communication: communication) }
    Shop::SeedAllocationRules.new.run
    Finance::SuggestAllocations.new(cash_entries: [entry]).run!
    entry.reload.allocation_suggestions.pending.first
  end

  it "la règle propose sans rien rattacher" do
    suggestion = suggestion_for("ARTISANAT EMILIE")

    expect(suggestion.general_account).to eq(artisanat)
    expect(suggestion.cash_entry.consignor).to be_nil
  end

  it "par défaut, rattache l'artisan du mot-clé (acceptation en masse)" do
    suggestion = suggestion_for("ARTISANAT EMILIE")

    described_class.new(suggestion: suggestion).run!

    expect(suggestion.cash_entry.reload.consignor).to eq(emilie)
  end

  it "rattache l'artisan choisi à l'écran, même contre le mot-clé" do
    suggestion = suggestion_for("ARTISANAT EMILIE")

    described_class.new(suggestion: suggestion, consignor: bruno).run!

    expect(suggestion.cash_entry.reload.consignor).to eq(bruno)
  end

  it "« personne » laisse la ligne sans artisan" do
    suggestion = suggestion_for("ARTISANAT EMILIE")

    described_class.new(suggestion: suggestion, consignor: nil).run!

    expect(suggestion.cash_entry.reload.consignor).to be_nil
    expect(suggestion.cash_entry.cash_allocations.first.general_account).to eq(artisanat)
  end

  it "vers un autre compte, aucun artisan" do
    suggestion = suggestion_for("EPICERIE")

    described_class.new(suggestion: suggestion, consignor: emilie).run!

    expect(suggestion.general_account).to eq(cellier)
    expect(suggestion.cash_entry.reload.consignor).to be_nil
  end
end
