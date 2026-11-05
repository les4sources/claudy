require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Michael, 2026-11-05 : la facture VOO #26 était le doublon de la #11, déjà
# payée. Une fois « À payer », plus rien ne permettait de l'annuler.
RSpec.describe PurchaseInvoices::Unpost do
  include FinanceBuilders
  include ActiveSupport::Testing::TimeHelpers

  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:charges) { build_general_account(code: "612101", name: "Téléphonie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte) { build_cash_account(entity, banque) }
  let!(:voo) { ThirdParty.create!(name: "Voo", kind: "supplier") }

  def facture(number: nil, total: 6_776)
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: voo, number: number,
                               issued_on: Date.new(2026, 10, 8), total_cents: total,
                               payment_reference: "+++471/0019/55561+++")
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: total)
    PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
  end

  def solde(code)
    JournalLine.joins(:general_account).where(general_accounts: { code: code }).sum("debit_cents - credit_cents")
  end

  it "contre-passe l'écriture d'achat et conteste la facture avec son motif" do
    doublon = facture
    expect(solde("612101")).to eq(6_776)

    described_class.new(purchase_invoice: doublon, reason: "Doublon de la facture #11", outcome: "disputed").run!

    doublon.reload
    expect(doublon).to be_disputed
    expect(doublon.dispute_reason).to eq("Doublon de la facture #11")
    expect(doublon.posted_at).to be_nil
    expect(solde("612101")).to eq(0)
    expect(solde("440000")).to eq(0)
    expect(JournalEntry.where(journal: "purchases").count).to eq(2)
    expect(JournalEntry.find_by(source: doublon)).to be_nil
    expect(PurchaseInvoice.payable).not_to include(doublon)
  end

  it "remet la facture à traiter, et un nouvel envoi passe une écriture neuve" do
    f = facture
    described_class.new(purchase_invoice: f, reason: "Mauvais compte").run!
    expect(f.reload).to be_to_process

    PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
    expect(f.reload).to be_to_pay
    expect(JournalEntry.where(journal: "purchases").count).to eq(3)
    expect(solde("612101")).to eq(6_776)
  end

  it "exige un motif" do
    expect { described_class.new(purchase_invoice: facture, reason: " ").run! }
      .to raise_error(described_class::Refused, /pourquoi/i)
  end

  it "refuse une facture dont un paiement est déjà rapproché" do
    f = facture
    entry = build_cash_entry(compte, amount_cents: -6_776, label: "Domiciliation Orange")
    Finance::RecordInvoicePayment.new(purchase_invoice: f, cash_entry: entry).run!

    expect(described_class.refusal_for(f.reload)).to be_present
    expect { described_class.new(purchase_invoice: f, reason: "Doublon").run! }.to raise_error(described_class::Refused)
  end

  it "date la contre-passation du jour quand le mois de la facture est arrêté" do
    f = facture
    MonthClosing.create!(period_month: Date.new(2026, 10, 1), closed_at: Time.current)

    travel_to(Date.new(2026, 11, 5)) do
      described_class.new(purchase_invoice: f, reason: "Doublon").run!
    end

    miroir = JournalEntry.where.not(reversal_of_id: nil).sole
    expect(miroir.entry_date).to eq(Date.new(2026, 11, 5))
  end
end
