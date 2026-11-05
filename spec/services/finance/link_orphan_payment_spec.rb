require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Michael, 2026-11-05 : la domiciliation VOO du 15/10 avait été affectée au
# 440000 par la règle « Orange Belgium », sans la facture #10, qui restait
# « À payer ». On la retrouve, on la relie, on ne repaie pas.
RSpec.describe Finance::LinkOrphanPayment do
  include FinanceBuilders

  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:charges) { build_general_account(code: "612101", name: "Téléphonie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte) { build_cash_account(entity, banque) }
  let!(:voo) { ThirdParty.create!(name: "Voo", kind: "supplier") }

  let!(:facture) do
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: voo, number: "411281108745",
                               issued_on: Date.new(2026, 10, 9), due_on: Date.new(2026, 10, 27),
                               total_cents: 1_815, payment_reference: "+++453/7084/34944+++")
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: 1_815)
    PurchaseInvoices::Advance.new(purchase_invoice: f).submit!
  end

  # Ce que fait une règle d'affectation : 440000, sans tiers ni pièce, puis
  # la ligne se comptabilise.
  def ligne_orpheline(amount_cents: -1_815, date: Date.new(2026, 10, 15), communication: "101 453708434944",
                      counterparty: "ORANGE BELGIUM")
    entry = build_cash_entry(compte, amount_cents: amount_cents, entry_date: date, label: counterparty)
    entry.update!(communication: communication, counterparty_name: counterparty)
    allocate(entry, account: fournisseurs, amount_cents: amount_cents, entity: entity)
    Accounting::PostCashEntry.new(cash_entry: entry.reload).run!
    entry.reload
  end

  describe Finance::OrphanSupplierPayments do
    it "trouve la sortie qui cite la communication structurée de la facture" do
      entry = ligne_orpheline

      candidates = described_class.new(invoices: [facture]).for(facture)

      expect(candidates.map(&:cash_entry)).to eq([entry])
      expect(candidates.first.confidence).to eq(99)
      expect(candidates.first.reason).to include("+++453/7084/34944+++")
    end

    it "se contente du montant autour de l'échéance, sans autre indice" do
      ligne_orpheline(communication: "127261026110BE67TEC0465607720", date: Date.new(2026, 10, 26))

      expect(described_class.new(invoices: [facture]).for(facture).first.confidence).to eq(60)
    end

    it "ignore un autre montant, une ligne bien plus ancienne ou une affectation au nom d'un autre tiers" do
      ligne_orpheline(amount_cents: -1_816)
      ligne_orpheline(date: Date.new(2026, 8, 1))
      autre = ligne_orpheline(communication: "rien")
      autre.cash_allocations.sole.update_columns(third_party_id: ThirdParty.create!(name: "Proximus", kind: "supplier").id)

      expect(described_class.new(invoices: [facture]).for(facture)).to be_empty
    end

    it "ne propose pas une sortie déjà reliée à une facture" do
      entry = build_cash_entry(compte, amount_cents: -1_815, entry_date: Date.new(2026, 10, 15), label: "Orange")
      autre = PurchaseInvoice.create!(legal_entity: entity, third_party: voo, number: "X", issued_on: Date.new(2026, 10, 1),
                                      total_cents: 1_815)
      autre.purchase_invoice_lines.create!(general_account: charges, amount_cents: 1_815)
      PurchaseInvoices::Advance.new(purchase_invoice: autre).submit!
      Finance::RecordInvoicePayment.new(purchase_invoice: autre, cash_entry: entry).run!

      expect(described_class.new(invoices: [facture.reload]).for(facture)).to be_empty
    end
  end

  it "relie l'affectation à la facture, qui passe payée, et y pose le tiers en repassant l'écriture" do
    entry = ligne_orpheline
    allocation = entry.cash_allocations.sole

    result = described_class.new(purchase_invoice: facture, allocation: allocation).run!

    expect(result.invoice).to be_paid
    expect(result.invoice.paid_on).to eq(Date.new(2026, 10, 15))
    expect(allocation.reload.document).to eq(facture)
    expect(allocation.third_party).to eq(voo)
    expect(result.reposted).to be(true)
    expect(entry.reload).to be_posted
    ligne_440 = entry.journal_entry.journal_lines.joins(:general_account).find_by(general_accounts: { code: "440000" })
    expect(ligne_440.third_party).to eq(voo)
    expect(JournalLine.joins(:general_account).where(general_accounts: { code: "612101" }).sum("debit_cents - credit_cents"))
      .to eq(1_815)
  end

  it "sur un mois arrêté, relie la pièce sans toucher à l'écriture" do
    entry = ligne_orpheline
    MonthClosing.create!(period_month: Date.new(2026, 10, 1), closed_at: Time.current)
    ecriture = entry.journal_entry

    result = described_class.new(purchase_invoice: facture, allocation: entry.cash_allocations.sole).run!

    expect(result.invoice).to be_paid
    expect(result.reposted).to be(false)
    expect(entry.reload.journal_entry).to eq(ecriture)
    expect(JournalEntry.where.not(reversal_of_id: nil)).to be_empty
  end

  it "refuse une affectation qui ne peut pas solder la facture" do
    entry = ligne_orpheline(amount_cents: -2_000)

    expect { described_class.new(purchase_invoice: facture, allocation: entry.cash_allocations.sole).run! }
      .to raise_error(described_class::Refused, /montant exact/)
  end
end
