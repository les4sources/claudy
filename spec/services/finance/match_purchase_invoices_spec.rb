require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 4 — proposer une facture d'achat sur une ligne bancaire.
#
# L'invariant du rapprochement assisté (B4) : ce service PROPOSE, il n'écrit
# jamais. Une machine qui affecte seule finit par affecter mal, et personne ne
# le voit avant l'arrêté annuel.
RSpec.describe Finance::MatchPurchaseInvoices do
  include FinanceBuilders

  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte) { build_cash_account(entity, banque) }
  let!(:antargaz) { ThirdParty.create!(name: "Antargaz", kind: "supplier", iban: "BE68539007547034") }
  let!(:luminus) { ThirdParty.create!(name: "Luminus", kind: "supplier") }

  def facture(tiers: antargaz, total: 12_000, number: "F-1", payable: true)
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: tiers, number: number,
                               issued_on: Date.new(2026, 6, 1), total_cents: total)
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: total)
    payable ? PurchaseInvoices::Advance.new(purchase_invoice: f).submit! : f.reload
  end

  def ligne(amount_cents: -12_000, iban: nil)
    entry = build_cash_entry(compte, amount_cents: amount_cents, label: "Virement sortant")
    entry.update!(counterparty_iban: iban) if iban
    entry
  end

  describe "#for_entry" do
    it "propose la facture dont le tiers porte l'IBAN de la ligne, avec sa raison" do
      f = facture
      matches = described_class.new.for_entry(ligne(amount_cents: -50_000, iban: "BE68 5390 0754 7034"))

      expect(matches.size).to eq(1)
      expect(matches.first.invoice).to eq(f)
      expect(matches.first.confidence).to eq(95)
      expect(matches.first.reason).to include("Antargaz")
    end

    it "propose la facture dont le montant restant égale exactement la ligne" do
      f = facture(tiers: luminus, total: 45_000, number: "L-9")
      matches = described_class.new.for_entry(ligne(amount_cents: -45_000))

      expect(matches.map(&:invoice)).to eq([f])
      expect(matches.first.confidence).to eq(70)
    end

    it "classe l'IBAN avant le montant quand les deux répondent" do
      iban_match = facture(total: 30_000, number: "A-1")
      montant_match = facture(tiers: luminus, total: 45_000, number: "L-9")

      matches = described_class.new.for_entry(ligne(amount_cents: -45_000, iban: "BE68539007547034"))

      expect(matches.map(&:invoice)).to eq([iban_match, montant_match])
    end

    it "ignore une ligne ENTRANTE : une facture d'achat ne se paie pas par une recette" do
      facture
      expect(described_class.new.for_entry(ligne(amount_cents: 12_000, iban: "BE68539007547034"))).to be_empty
    end

    it "ignore une ligne déjà affectée" do
      facture
      entry = ligne(iban: "BE68539007547034")
      entry.cash_allocations.create!(general_account: charges, legal_entity: entity, amount_cents: -12_000)

      expect(described_class.new.for_entry(entry.reload)).to be_empty
    end

    it "ne propose pas une facture qui n'est pas « à payer »" do
      facture(payable: false)
      expect(described_class.new.for_entry(ligne(amount_cents: -12_000))).to be_empty
    end

    it "ne propose plus une facture entièrement rapprochée" do
      f = facture
      autre = build_cash_entry(compte, amount_cents: -12_000, label: "Déjà payé")
      autre.cash_allocations.create!(general_account: fournisseurs, legal_entity: entity,
                                     third_party: antargaz, document: f, amount_cents: -12_000)

      expect(described_class.new.for_entry(ligne(amount_cents: -12_000))).to be_empty
    end

    # L'INVARIANT : proposer ne coûte rien, et surtout n'écrit rien.
    it "n'écrit AUCUNE allocation" do
      facture
      entry = ligne(iban: "BE68539007547034")

      expect { described_class.new.for_entry(entry) }.not_to change(CashAllocation, :count)
    end
  end

  describe "#for_entries" do
    it "ne renvoie une entrée que pour les lignes qui ont une proposition" do
      facture(total: 12_000)
      avec = ligne(amount_cents: -12_000)
      sans = ligne(amount_cents: -777)

      resultat = described_class.new.for_entries([avec, sans])

      expect(resultat.keys).to eq([avec.id])
    end
  end
end
