require "rails_helper"
require Rails.root.join("spec/support/finance_builders")
require Rails.root.join("spec/support/mail_intake_helpers")

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

  # Le précédent du même IBAN n'était juste qu'une fois sur deux (mesuré sur
  # 2025) : il n'est plus une proposition, seulement un indice pour Jev.
  describe "sans règle et sans Jev" do
    it "ne propose plus le précédent du même IBAN" do
      precedente = build_cash_entry(cash_account, amount_cents: -12_000, entry_date: Date.new(2026, 5, 15),
                                    label: "Facture de mai")
      precedente.update!(counterparty_iban: "BE11222233334444")
      allocate(precedente, account: energie, amount_cents: -12_000, entity: entity, team: technique)
      Accounting::PostCashEntry.new(cash_entry: precedente).run!

      expect { described_class.new.run! }.not_to change { AllocationSuggestion.count }
    end
  end

  describe "Jev, là où aucune règle ne s'applique" do
    before { Finance::AllocationHistory.reset! }

    let!(:precedente) do
      build_cash_entry(cash_account, amount_cents: -9_800, entry_date: Date.new(2026, 5, 15),
                       label: "Facture ENGIE ELECTRABEL").tap do |e|
        e.update!(counterparty_name: "ENGIE ELECTRABEL", counterparty_iban: "BE11 2222 3333 4444")
        allocate(e, account: energie, amount_cents: -9_800, entity: entity)
        Accounting::PostCashEntry.new(cash_entry: e).run!
      end
    end

    def jev_choosing(answer)
      MailIntakeHelpers::FakeJev.new { |_id, _question| answer }
    end

    it "propose le compte choisi par Jev au-dessus du seuil, avec un motif écrit par le code" do
      jev = jev_choosing("choice" => energie.to_s, "confidence" => 0.91)

      described_class.new(jev: jev).run!

      suggestion = entry.reload.allocation_suggestions.first
      expect(suggestion.source).to eq("jev")
      expect(suggestion.general_account).to eq(energie)
      expect(suggestion.confidence).to eq(91)
      expect(suggestion.rationale).to include("une ligne semblable déjà affectée à ce compte")
        .and include("ENGIE ELECTRABEL")
      expect(suggestion.rationale).to include("la dernière ligne de cette contrepartie aussi")
    end

    it "ne donne à Jev que des comptes actifs déjà utilisés, et aucun IBAN" do
      jev = jev_choosing("choice" => "aucun", "confidence" => 0.9)

      described_class.new(jev: jev).run!

      call = jev.calls.first
      options = call[:questions]["compte"][:criteria].keys
      expect(options).to contain_exactly(energie.to_s, "aucun")
      expect(call[:state].to_json).not_to include("BE11")
      expect(call[:state]["historique_meme_contrepartie"].first["compte"]).to eq(energie.to_s)
    end

    it "ne propose pas un compte devenu inactif" do
      energie.update!(active: false)
      jev = jev_choosing("choice" => energie.to_s, "confidence" => 0.99)

      expect { described_class.new(jev: jev).run! }.not_to change { AllocationSuggestion.count }
      expect(jev.calls).to be_empty
    end

    it "ne propose rien sous le seuil, et ne redemande pas la même ligne" do
      jev = jev_choosing("choice" => energie.to_s, "confidence" => 0.62)

      expect { described_class.new(jev: jev).run! }.not_to change { AllocationSuggestion.count }
      expect(entry.reload.jev_checked_at).to be_present

      described_class.new(jev: jev).run!
      expect(jev.calls.size).to eq(1)
    end

    it "ne retient pas une réponse qui n'est pas l'une des options" do
      jev = jev_choosing("choice" => "999999 Compte inventé", "confidence" => 0.99)

      expect { described_class.new(jev: jev).run! }.not_to change { AllocationSuggestion.count }
    end

    it "laisse la règle passer avant Jev" do
      build_rule(label: "Énergie", account: entretien, position: 1, counterparty_name_contains: "ENGIE")
      jev = jev_choosing("choice" => energie.to_s, "confidence" => 0.99)

      described_class.new(jev: jev).run!

      expect(jev.calls).to be_empty
      expect(entry.reload.allocation_suggestions.first.source).to eq("rule")
    end

    it "redemandera plus tard quand Jev est injoignable" do
      jev = MailIntakeHelpers::FakeJev.new { raise Jev::Client::Error, "Jev injoignable (Net::ReadTimeout)" }

      expect { described_class.new(jev: jev).run! }.not_to change { AllocationSuggestion.count }
      expect(entry.reload.jev_checked_at).to be_nil
    end

    it "ne demande rien à Jev s'il n'est pas configuré" do
      jev = MailIntakeHelpers::FakeJev.new(configured: false)

      described_class.new(jev: jev).run!

      expect(jev.calls).to be_empty
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
