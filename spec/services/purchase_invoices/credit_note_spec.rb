require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Les notes de crédit fournisseurs (Michael, 2026-11-01) : même pièce qu'une
# facture, montant positif, écriture à l'envers ; imputée sur la facture
# qu'elle corrige, ou remboursée par le fournisseur.
RSpec.describe "Note de crédit d'achat" do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:charges) { build_general_account(code: "610000", name: "Matériel", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte) { build_cash_account(entity, banque) }
  let!(:fournisseur) { ThirdParty.create!(name: "Frennet", kind: "supplier") }

  def piece(kind:, total:, number:, credited: nil)
    doc = PurchaseInvoice.create!(legal_entity: entity, third_party: fournisseur, number: number, kind: kind,
                                  credited_invoice: credited, issued_on: Date.new(2026, 10, 23), total_cents: total)
    doc.purchase_invoice_lines.create!(general_account: charges, amount_cents: total)
    PurchaseInvoices::Advance.new(purchase_invoice: doc.reload).submit!
  end

  def facture(total = 100_000, number: "26001") = piece(kind: "invoice", total: total, number: number)
  def note(total = 30_000, credited: nil, number: "NC-1") = piece(kind: "credit_note", total: total, number: number, credited: credited)

  def ligne(cents, day: Date.new(2026, 10, 25))
    build_cash_entry(compte, amount_cents: cents, entry_date: day, label: "Frennet")
  end

  it "passe l'écriture à l'envers : 440000 au débit, la charge au crédit" do
    nc = note
    entry = JournalEntry.find_by(source: nc, journal: "purchases")

    debit = entry.journal_lines.select { |l| l.debit_cents.positive? }
    credit = entry.journal_lines.select { |l| l.credit_cents.positive? }
    expect(debit.map { |l| [l.general_account.code, l.debit_cents, l.third_party_id] }).to eq([["440000", 30_000, fournisseur.id]])
    expect(credit.map { |l| [l.general_account.code, l.credit_cents] }).to eq([["610000", 30_000]])
  end

  it "s'impute sur la facture qu'elle corrige, qui n'attend plus que le reste" do
    f = facture
    nc = note(credited: f)

    expect(nc.reload.status).to eq("paid")
    expect(nc.status_label).to eq("Imputée")
    expect(f.reload.payable_amount_cents).to eq(70_000)
    expect(f.remaining_cents).to eq(70_000)
    expect(f.status).to eq("to_pay")
  end

  it "solde la facture qu'elle annule entièrement" do
    f = facture(30_000)
    note(30_000, credited: f)

    expect(f.reload.status).to eq("paid")
  end

  it "attend le remboursement quand la facture était déjà payée" do
    f = facture
    out = ligne(-100_000)
    Finance::RecordInvoicePayment.new(purchase_invoice: f, cash_entry: out).run!
    expect(f.reload.status).to eq("paid")

    nc = note(credited: f)
    expect(nc.reload.status).to eq("to_pay")
    expect(nc.status_label).to eq("À rembourser")
    expect(nc.remaining_cents).to eq(30_000)
    expect(f.reload.status).to eq("paid")
  end

  it "se rembourse par une ligne ENTRANTE, pas sortante" do
    nc = note
    expect { Finance::RecordInvoicePayment.new(purchase_invoice: nc, cash_entry: ligne(-30_000)).run! }
      .to raise_error(Finance::RecordInvoicePayment::WrongDirection)

    entree = ligne(30_000)
    expect(Finance::MatchPurchaseInvoices.new.for_entry(entree).map(&:invoice)).to eq([nc])

    Finance::RecordInvoicePayment.new(purchase_invoice: nc, cash_entry: entree).run!
    expect(entree.cash_allocations.sole.amount_cents).to eq(30_000)
    expect(nc.reload.status).to eq("paid")
    expect(nc.status_label).to eq("Remboursée")
  end

  it "ne va jamais dans la file « À payer »" do
    note
    f = facture

    expect(Finance::PayableQueue.new.rows.grep(PurchaseInvoice)).to eq([f])
    expect(Finance::MatchPurchaseInvoices.new.for_entry(ligne(-30_000)).map(&:invoice)).not_to include(be_credit_note)
  end

  it "refuse une facture corrigée d'un autre fournisseur" do
    autre = ThirdParty.create!(name: "Antargaz", kind: "supplier")
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: autre, number: "A-1",
                                issued_on: Date.new(2026, 10, 1), total_cents: 1_000)
    nc = PurchaseInvoice.new(legal_entity: entity, third_party: fournisseur, kind: "credit_note", credited_invoice: f,
                             issued_on: Date.new(2026, 10, 23), total_cents: 1_000)

    expect(nc).not_to be_valid
    expect(nc.errors[:credited_invoice]).to include("n'est pas du même fournisseur")
  end

  it "accepte une note de crédit au même numéro qu'une facture du fournisseur" do
    facture(number: "26030")

    expect { note(number: "26030") }.not_to raise_error
  end
end
