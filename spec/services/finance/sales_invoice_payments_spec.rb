require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Encaisser toute facture du registre (Michael, 2026-10-30) : une facture
# passée au journal Ventes s'impute sur le 400000 du tiers, en un ou plusieurs
# virements ; un virement peut solder deux factures ; la communication qui
# cite le numéro désigne la facture.
RSpec.describe Finance::RecordSalesInvoicePayment do
  include FinanceBuilders

  let!(:fondation) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:exercice) { build_fiscal_year(fondation) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:compte_bancaire) { build_cash_account(fondation, banque) }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4, nature: "asset") }
  let!(:salles) { build_general_account(code: "701002", name: "Location de salles", klass: 7, nature: "revenue") }
  let!(:saint_gilles) { ThirdParty.create!(name: "Commune de Saint-Gilles", kind: "customer") }

  def facture(numero, cents, kind: "invoice", corrigee: nil)
    SalesInvoices::Record.new(attributes: { legal_entity_id: fondation.id, third_party_id: saint_gilles.id, number: numero,
                                            issued_on: Date.new(2026, 9, 1), total_cents: cents, kind: kind,
                                            credited_invoice_id: corrigee&.id,
                                            sales_invoice_lines_attributes: [{ general_account_id: salles.id, net_cents: cents, vat_rate: 0 }] }).run!
  end

  def ligne(cents, communication: nil)
    entry = build_cash_entry(compte_bancaire, amount_cents: cents, entry_date: Date.new(2026, 9, 20), label: "Virement Saint-Gilles")
    entry.update!(communication: communication) if communication
    entry
  end

  def encaisser(invoice, entry, montant = nil)
    Finance::RecordSalesInvoicePayment.new(sales_invoice: invoice, cash_entry: entry, amount_cents: montant).run!
  end

  it "impute la ligne sur le 400000 du tiers, sans nouvelle recette, et comptabilise la ligne" do
    f = facture("2026-047", 64_000)
    entry = ligne(64_000)

    encaisser(f, entry)

    allocation = entry.cash_allocations.sole
    expect(allocation).to have_attributes(general_account: clients, third_party: saint_gilles, document: f, amount_cents: 64_000)
    expect(f.reload).to have_attributes(status: "paid", paid_on: Date.new(2026, 9, 20), remaining_cents: 0)
    expect(entry.reload).to be_posted
    expect(JournalLine.joins(:general_account).where(general_accounts: { code: "701002" }).sum(:credit_cents)).to eq(64_000)
  end

  it "encaisse une facture payée en deux virements" do
    f = facture("2026-050", 100_000)

    encaisser(f, ligne(40_000))
    expect(f.reload).to have_attributes(status: "issued", remaining_cents: 60_000)

    encaisser(f, ligne(60_000))
    expect(f.reload).to have_attributes(status: "paid", remaining_cents: 0)
  end

  it "solde deux factures avec un seul virement" do
    a = facture("2026-051", 30_000)
    b = facture("2026-052", 20_000)
    entry = ligne(50_000)

    encaisser(a, entry)
    encaisser(b, entry.reload)

    expect([a.reload.status, b.reload.status]).to eq(%w[paid paid])
    expect(entry.reload).to be_posted
  end

  it "refuse de surpayer une facture" do
    f = facture("2026-053", 30_000)

    expect { encaisser(f, ligne(50_000), 40_000) }.to raise_error(described_class::TooMuch, /n'attend que/)
  end

  it "n'attend plus que le reste après une note de crédit" do
    f = facture("2026-061", 50_000)
    facture("2026-062", 10_000, kind: "credit_note", corrigee: f)
    entry = ligne(40_000)

    encaisser(f, entry)

    expect(entry.cash_allocations.sole.amount_cents).to eq(40_000)
    expect(f.reload.status).to eq("paid")
  end

  it "rembourse une note de crédit non imputée depuis une ligne sortante" do
    note = facture("2026-070", 15_000, kind: "credit_note")
    sortie = ligne(-15_000)

    encaisser(note, sortie)

    expect(sortie.cash_allocations.sole).to have_attributes(general_account: clients, amount_cents: -15_000)
    expect(note.reload).to have_attributes(status: "paid", status_label: "Remboursée")
  end

  describe Finance::MatchSalesInvoices do
    it "propose la facture dont la communication cite le numéro, avant le montant" do
      cite = facture("2026-047", 64_000)
      meme_montant = facture("2026-048", 30_000)

      matches = described_class.new.for_entry(ligne(30_000, communication: "Facture 2026-047 salle"))

      expect(matches.first).to have_attributes(invoice: cite, confidence: 95)
      expect(matches.map(&:invoice)).to include(meme_montant)
    end

    it "propose la facture dont la communication structurée est reprise, même écrite autrement" do
      f = facture("2026-049", 64_000)
      f.update_columns(payment_reference: "+++090/9337/55493+++")

      matches = described_class.new.for_entry(ligne(10_000, communication: "090 9337 55493"))

      expect(matches.sole).to have_attributes(invoice: f, confidence: 95)
    end

    it "ne lit pas un numéro dans un autre" do
      facture("2026-04", 64_000)

      expect(described_class.new.for_entry(ligne(1_000, communication: "Facture 2026-047"))).to be_empty
    end

    it "propose le reste dû d'une facture entamée, et une ligne entamée" do
      f = facture("2026-050", 100_000)
      encaisser(f, ligne(40_000))
      entry = ligne(80_000)
      entry.cash_allocations.create!(general_account: salles, legal_entity: fondation, amount_cents: 20_000)

      expect(described_class.new.for_entry(entry.reload).map(&:invoice)).to eq([f])
    end
  end
end
