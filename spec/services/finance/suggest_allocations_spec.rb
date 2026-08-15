require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# L'invariant central du rapprochement assisté : le moteur PROPOSE et n'affecte
# jamais. Une machine qui affecte seule finit toujours par affecter mal, et
# personne ne le voit avant l'arrêté annuel.
RSpec.describe Finance::SuggestAllocations do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:energie) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let(:entretien) { build_general_account(code: "611000", name: "Entretien", klass: 6, nature: "expense") }
  let(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }
  let(:cash_account) { build_cash_account(entity, bank_account) }

  let!(:entry) do
    build_cash_entry(cash_account, amount_cents: -12_000, label: "Facture").tap do |e|
      e.update!(counterparty_name: "ENGIE ELECTRABEL", counterparty_iban: "BE11222233334444")
    end
  end

  def build_rule(label:, account:, position:, **criteria)
    AllocationRule.create!({ label: label, general_account: account, legal_entity: entity,
                             team: technique, position: position }.merge(criteria))
  end

  it "ne crée aucune allocation — il propose" do
    build_rule(label: "Énergie", account: energie, position: 1, counterparty_name_contains: "ENGIE")

    expect { described_class.new.run! }.not_to change { CashAllocation.count }
    expect(entry.reload.allocation_suggestions.count).to eq(1)
    expect(entry.status).to eq("pending")
  end

  # L'ordre est signifiant : il permet de poser une règle très précise avant une
  # règle générale.
  it "retient la PREMIÈRE règle qui correspond" do
    build_rule(label: "Générale", account: entretien, position: 2, direction: "outgoing")
    build_rule(label: "Précise", account: energie, position: 1, counterparty_name_contains: "ENGIE")

    described_class.new.run!

    suggestion = entry.reload.allocation_suggestions.first
    expect(suggestion.general_account).to eq(energie)
    expect(suggestion.rationale).to include("Précise")
  end

  it "ne propose pas deux fois sur la même ligne" do
    build_rule(label: "Énergie", account: energie, position: 1, counterparty_name_contains: "ENGIE")

    described_class.new.run!
    expect { described_class.new.run! }.not_to change { AllocationSuggestion.count }
  end

  it "ignore les règles inactives" do
    build_rule(label: "Énergie", account: energie, position: 1, counterparty_name_contains: "ENGIE", active: false)

    expect { described_class.new.run! }.not_to change { AllocationSuggestion.count }
  end

  # Le vrai gain du quotidien : au deuxième virement d'un tiers récurrent, ça se
  # propose tout seul sans qu'on ait écrit la moindre règle.
  describe "l'apprentissage par IBAN" do
    it "propose le précédent d'une ligne du même IBAN déjà affectée" do
      precedente = build_cash_entry(cash_account, amount_cents: -12_000, entry_date: Date.new(2026, 5, 15),
                                    label: "Facture de mai")
      precedente.update!(counterparty_iban: "BE11222233334444")
      allocate(precedente, account: energie, amount_cents: -12_000, entity: entity, team: technique)
      Accounting::PostCashEntry.new(cash_entry: precedente).run!

      described_class.new.run!

      suggestion = entry.reload.allocation_suggestions.first
      expect(suggestion.source).to eq("iban_history")
      expect(suggestion.general_account).to eq(energie)
      expect(suggestion.rationale).to include("même IBAN")
      # Un précédent n'est pas une intention : la confiance est bornée plus bas.
      expect(suggestion.confidence).to be < 80
    end

    it "ne propose rien sans précédent" do
      expect { described_class.new.run! }.not_to change { AllocationSuggestion.count }
    end
  end

  # Reproposer ce qui vient d'être refusé transformerait le refus en formalité :
  # on finirait par accepter d'épuisement.
  it "ne represente pas une suggestion déjà refusée" do
    build_rule(label: "Énergie", account: energie, position: 1, counterparty_name_contains: "ENGIE")
    described_class.new.run!
    entry.reload.allocation_suggestions.first.update!(status: "rejected", decided_at: Time.current)

    expect { described_class.new.run! }.not_to change { AllocationSuggestion.count }
  end

  it "utilise le code transaction porté par la ligne, pas sa référence externe" do
    entry.update!(transaction_code: "01500000")
    build_rule(label: "Virements", account: energie, position: 1, transaction_code: "015")

    described_class.new.run!

    expect(entry.reload.allocation_suggestions.first.rationale).to include("code transaction 015")
  end

  it "ne propose rien sur une ligne exclue ou déjà comptabilisée" do
    build_rule(label: "Énergie", account: energie, position: 1, counterparty_name_contains: "ENGIE")
    entry.exclude!("Doublon")

    expect { described_class.new.run! }.not_to change { AllocationSuggestion.count }
  end
end
