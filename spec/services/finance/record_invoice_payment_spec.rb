require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 4 — le virement qui paie une facture d'achat.
#
# Décision 4 : le paiement est un RAPPROCHEMENT. Rien n'est coché — l'allocation
# sur le 440000 avec la facture en document est ce qui la fait passer `paid`.
RSpec.describe Finance::RecordInvoicePayment do
  include FinanceBuilders

  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte) { build_cash_account(entity, banque) }
  let!(:antargaz) { ThirdParty.create!(name: "Antargaz", kind: "supplier", iban: "BE68539007547034") }

  let(:facture) do
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: antargaz, number: "F-1",
                               issued_on: Date.new(2026, 6, 1), total_cents: 12_000)
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: 12_000)
    PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
  end

  def ligne(amount_cents: -12_000)
    build_cash_entry(compte, amount_cents: amount_cents, label: "Virement Antargaz")
  end

  it "affecte la ligne sur le 440000, avec la facture en document et son tiers" do
    entry = ligne
    described_class.new(purchase_invoice: facture, cash_entry: entry).run!

    allocation = entry.reload.cash_allocations.sole
    expect(allocation.general_account).to eq(fournisseurs)
    expect(allocation.document).to eq(facture)
    expect(allocation.third_party).to eq(antargaz)
    expect(allocation.amount_cents).to eq(-12_000)
  end

  it "fait passer la facture en « payée », sans que rien ne soit coché" do
    described_class.new(purchase_invoice: facture, cash_entry: ligne).run!

    expect(facture.reload).to be_paid
    expect(facture.paid_on).to eq(Date.new(2026, 6, 15))
  end

  it "comptabilise la ligne une fois qu'elle est entièrement affectée" do
    entry = ligne
    described_class.new(purchase_invoice: facture, cash_entry: entry).run!

    expect(entry.reload).to be_posted
  end

  # Un paiement partiel reste VISIBLE comme tel : la facture ne ment pas.
  it "laisse la facture « à payer » sur un paiement partiel" do
    described_class.new(purchase_invoice: facture, cash_entry: ligne(amount_cents: -5_000)).run!

    expect(facture.reload).to be_to_pay
    expect(facture.allocated_cents).to eq(5_000)
    expect(facture.remaining_cents).to eq(7_000)
  end

  it "solde le reste au second virement" do
    described_class.new(purchase_invoice: facture, cash_entry: ligne(amount_cents: -5_000)).run!
    described_class.new(purchase_invoice: facture, cash_entry: ligne(amount_cents: -7_000)).run!

    expect(facture.reload).to be_paid
  end

  # Le rapprochement fonctionne dans les DEUX sens : défaire l'affectation
  # redonne la dette. Un état qui ne sait que monter est un état faux.
  it "refait passer la facture « à payer » quand on défait l'affectation" do
    entry = ligne
    described_class.new(purchase_invoice: facture, cash_entry: entry).run!
    expect(facture.reload).to be_paid

    # Le vrai chemin : on annule la passation (contre-passation) AVANT de
    # défaire l'affectation — une ligne comptabilisée ne se réaffecte pas.
    Accounting::UnpostCashEntry.new(cash_entry: entry.reload).run!
    entry.reload.cash_allocations.each(&:destroy!)

    expect(facture.reload).to be_to_pay
    expect(facture.paid_on).to be_nil
  end

  describe "ce qu'il refuse" do
    it "refuse une ligne ENTRANTE" do
      expect { described_class.new(purchase_invoice: facture, cash_entry: ligne(amount_cents: 12_000)).run! }
        .to raise_error(described_class::WrongDirection)
    end

    it "refuse une facture qui n'est pas « à payer »" do
      brouillon = PurchaseInvoice.create!(legal_entity: entity, third_party: antargaz, number: "F-2",
                                          issued_on: Date.new(2026, 6, 1), total_cents: 500)

      expect { described_class.new(purchase_invoice: brouillon, cash_entry: ligne).run! }
        .to raise_error(described_class::NotPayable, /À payer/)
    end

    it "refuse d'affecter plus que ce que la facture attend" do
      expect {
        described_class.new(purchase_invoice: facture, cash_entry: ligne(amount_cents: -30_000),
                            amount_cents: 20_000).run!
      }.to raise_error(described_class::TooMuch)
    end

    # Une facture soldée est PASSÉE en « payée » : c'est le premier garde-fou
    # qui répond, et il dit pourquoi — on ne repaie pas une facture payée.
    it "refuse une facture déjà entièrement rapprochée" do
      described_class.new(purchase_invoice: facture, cash_entry: ligne).run!

      expect { described_class.new(purchase_invoice: facture.reload, cash_entry: ligne).run! }
        .to raise_error(described_class::NotPayable, /payée/)
    end
  end

  # Un virement groupé paie plusieurs factures : sans plafond, la seconde
  # allocation se ferait refuser par `within_entry_amount` avec un message qui
  # ne dit rien du problème.
  it "ne consomme que ce que la facture attend sur une ligne plus grosse" do
    entry = ligne(amount_cents: -30_000)
    described_class.new(purchase_invoice: facture, cash_entry: entry).run!

    expect(entry.reload.cash_allocations.sole.amount_cents).to eq(-12_000)
    expect(entry).not_to be_posted
  end
end
