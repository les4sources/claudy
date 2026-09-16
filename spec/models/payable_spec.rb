require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 4 — le contrat `Payable`.
#
# Cinq choses suffisent à payer : combien, à qui, sur quel compte, avec quelle
# communication, pour quand. `PurchaseInvoice` est le premier à le remplir ;
# les notes de frais, relevés de porteurs, parts d'événements et règlements de
# dépôt-vente suivront. On teste le contrat À TRAVERS elle : un concern testé
# sur une classe fictive ne prouve rien du branchement réel.
RSpec.describe Payable do
  include FinanceBuilders

  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte) { build_cash_account(entity, banque) }
  let!(:antargaz) { ThirdParty.create!(name: "Antargaz", kind: "supplier", iban: "BE68539007547034") }

  def facture(total: 12_000, number: "F-1", due_on: nil, tiers: antargaz)
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: tiers, number: number,
                               issued_on: Date.new(2026, 6, 1), due_on: due_on, total_cents: total)
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: total)
    PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
  end

  def rapprocher(invoice, amount_cents)
    entry = build_cash_entry(compte, amount_cents: -amount_cents, label: "Virement")
    entry.cash_allocations.create!(general_account: fournisseurs, legal_entity: entity,
                                   third_party: invoice.third_party, document: invoice,
                                   amount_cents: -amount_cents)
    invoice.reload
  end

  it "répond aux cinq questions du virement" do
    f = facture(due_on: Date.new(2026, 7, 15))

    expect(f.payable_amount_cents).to eq(12_000)
    expect(f.payable_beneficiary).to eq("Antargaz")
    expect(f.payable_iban).to eq("BE68539007547034")
    expect(f.payable_communication).to eq("F-1")
    expect(f.payable_due_on).to eq(Date.new(2026, 7, 15))
  end

  # Un virement muet est un virement que le fournisseur ne rapproche pas : à
  # défaut de son numéro, on met le nôtre.
  it "retombe sur notre propre référence quand la facture n'a pas de numéro" do
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: antargaz,
                                issued_on: Date.new(2026, 6, 1), total_cents: 500)

    expect(f.payable_communication).to eq("Facture ##{f.id}")
  end

  describe "ce que le rapprochement déduit" do
    it "part de zéro rapproché et du total dû" do
      f = facture

      expect(f.allocated_cents).to eq(0)
      expect(f.remaining_cents).to eq(12_000)
      expect(f).not_to be_payable_settled
      expect(f).not_to be_partially_paid
    end

    it "voit un paiement partiel comme partiel" do
      f = rapprocher(facture, 5_000)

      expect(f.allocated_cents).to eq(5_000)
      expect(f.remaining_cents).to eq(7_000)
      expect(f).to be_partially_paid
      expect(f).not_to be_payable_settled
    end

    it "se considère soldé dès que les allocations couvrent le total" do
      f = rapprocher(facture, 12_000)

      expect(f).to be_payable_settled
      expect(f).not_to be_partially_paid
    end
  end

  describe "le retard" do
    it "compte les jours depuis l'échéance dépassée" do
      f = facture(due_on: Date.current - 7)

      expect(f).to be_payable_overdue
      expect(f.payable_days_late).to eq(7)
    end

    it "n'est jamais en retard sans échéance : rien n'a été promis" do
      expect(facture(due_on: nil)).not_to be_payable_overdue
    end

    # Une dette soldée n'est plus en retard, même échue : elle est payée.
    it "cesse d'être en retard dès qu'il est soldé" do
      f = rapprocher(facture(due_on: Date.current - 7), 12_000)

      expect(f).not_to be_payable_overdue
      expect(f.payable_days_late).to eq(0)
    end
  end

  # On ne CACHE jamais un payable sans IBAN — on le marque. Faire disparaître
  # une dette parce qu'il manque une coordonnée est la meilleure façon de ne
  # jamais la payer.
  it "se dit « pas prêt » sans IBAN, sans cesser d'exister" do
    sans = ThirdParty.create!(name: "Le Maraîcher", kind: "supplier")
    f = facture(tiers: sans, number: "M-1")

    expect(f).not_to be_payable_ready
    expect(f.payable_amount_cents).to eq(12_000)
    expect(PurchaseInvoice.payable).to include(f)
  end
end
