require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 4 — « Payée en caisse ».
#
# Le fournisseur du marché repart avec ses billets. Ça ne se note pas « payée » :
# ça crée une VRAIE sortie de caisse. Sans quoi la dette resterait au grand livre
# alors que l'argent est parti, et la caisse serait fausse d'autant.
RSpec.describe PurchaseInvoices::PayInCash do
  include FinanceBuilders

  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:compte_caisse) { build_general_account(code: "570000", name: "Caisse") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:caisse) { build_cash_account(entity, compte_caisse, name: "Caisse épicerie", kind: "cash") }
  let!(:maraicher) { ThirdParty.create!(name: "Le Maraîcher", kind: "supplier") }

  let(:facture) do
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: maraicher, number: "M-3",
                               issued_on: Date.new(2026, 6, 1), total_cents: 12_000)
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: 12_000)
    PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
  end

  it "crée une sortie de caisse affectée sur le 440000, avec la facture en document" do
    expect { described_class.new(purchase_invoice: facture, paid_on: Date.new(2026, 6, 20)).run! }
      .to change(CashEntry, :count).by(1)

    entry = CashEntry.order(:id).last
    expect(entry.cash_account).to eq(caisse)
    expect(entry.amount_cents).to eq(-12_000)
    expect(entry.entry_date).to eq(Date.new(2026, 6, 20))

    allocation = entry.cash_allocations.sole
    expect(allocation.general_account).to eq(fournisseurs)
    expect(allocation.document).to eq(facture)
    expect(allocation.third_party).to eq(maraicher)
  end

  it "fait passer la facture en « payée » par le seul rapprochement" do
    described_class.new(purchase_invoice: facture, paid_on: Date.new(2026, 6, 20)).run!

    expect(facture.reload).to be_paid
    expect(facture.paid_on).to eq(Date.new(2026, 6, 20))
  end

  it "comptabilise la sortie de caisse" do
    described_class.new(purchase_invoice: facture).run!

    expect(CashEntry.order(:id).last).to be_posted
  end

  it "ne règle que le RESTE quand une partie est déjà rapprochée" do
    banque = build_cash_account(entity, build_general_account(code: "550000", name: "Banque"))
    acompte = build_cash_entry(banque, amount_cents: -5_000, label: "Acompte")
    acompte.cash_allocations.create!(general_account: fournisseurs, legal_entity: entity,
                                     third_party: maraicher, document: facture, amount_cents: -5_000)

    described_class.new(purchase_invoice: facture.reload).run!

    expect(CashEntry.order(:id).last.amount_cents).to eq(-7_000)
    expect(facture.reload).to be_paid
  end

  describe "ce qu'il refuse" do
    it "refuse une facture qui n'est pas « à payer »" do
      brouillon = PurchaseInvoice.create!(legal_entity: entity, third_party: maraicher, number: "M-9",
                                          issued_on: Date.new(2026, 6, 1), total_cents: 500)

      expect { described_class.new(purchase_invoice: brouillon).run! }
        .to raise_error(described_class::BadStatus)
    end

    it "refuse quand l'entité n'a aucune caisse" do
      caisse.update!(active: false)

      expect { described_class.new(purchase_invoice: facture).run! }
        .to raise_error(described_class::NoCashAccount, /Aucune caisse active/)
    end

    # Un mois arrêté ne bouge plus : y ajouter une sortie de caisse ferait
    # diverger l'arrêté de la réalité comptable.
    it "refuse d'écrire dans un mois arrêté" do
      MonthClosing.create!(period_month: Date.new(2026, 6, 1), closed_at: Time.current)

      expect { described_class.new(purchase_invoice: facture, paid_on: Date.new(2026, 6, 20)).run! }
        .to raise_error(described_class::MonthClosed)
    end
  end
end
