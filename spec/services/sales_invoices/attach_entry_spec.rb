require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Rattacher une écriture de vente existante (Michael, 2026-10-30) : la facture
# pointe l'écriture reprise sans en passer une nouvelle, et les encaissements
# déjà imputés au 400000 du tiers deviennent ses paiements.
RSpec.describe SalesInvoices::AttachEntry do
  include FinanceBuilders

  let!(:srl) { build_legal_entity(name: "Domaine d'Ahinvaux SRL", form: "srl").tap { |e| e.update!(vat_regime: "subject") } }
  let!(:fondation) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:exercice_srl) { build_fiscal_year(srl) }
  let!(:exercice_fondation) { build_fiscal_year(fondation) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:compte_bancaire) { build_cash_account(fondation, banque) }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4, nature: "asset") }
  let!(:tva_due) { build_general_account(code: "451000", name: "TVA à payer", klass: 4, nature: "liability") }
  let!(:pains) { build_general_account(code: "700000", name: "Ventes de pains", klass: 7, nature: "revenue") }
  let!(:salles) { build_general_account(code: "701002", name: "Location de salles", klass: 7, nature: "revenue") }
  let!(:ekikrok) { ThirdParty.create!(name: "Ekikrok", kind: "customer", code: "EKIKROK") }
  let!(:saint_gilles) { ThirdParty.create!(name: "Commune de Saint-Gilles", kind: "customer", code: "STGILLES") }

  before { Accounting::ImportLedgerDocument.reset_cache! }

  # Une pièce reprise de Winbooks : « 2026:VENTES:2026-100 ».
  def reprise(numero, ttc, tiers: ekikrok, tva: 0, entite: srl, date: Date.new(2026, 10, 1), libelle: nil)
    Accounting::ImportLedgerDocument.new(
      legal_entity: entite, source_system: "winbooks", external_ref: "2026:VENTES:#{numero}", journal: "sales",
      entry_date: date, label: libelle || "#{numero} #{tiers.name} - pains",
      lines: [
        { account_code: "400000", debit_cents: ttc, credit_cents: 0, third_party_code: tiers.code },
        { account_code: "700000", debit_cents: 0, credit_cents: ttc - tva },
        (tva.positive? ? { account_code: "451000", debit_cents: 0, credit_cents: tva } : nil)
      ].compact
    ).run!
  end

  # Un virement déjà imputé au 400000 du tiers, et comptabilisé.
  def encaissement(cents, tiers: saint_gilles, communication: nil, date: Date.new(2026, 10, 10))
    entry = build_cash_entry(compte_bancaire, amount_cents: cents, entry_date: date, label: "Virement #{tiers.name}")
    entry.update!(communication: communication) if communication
    entry.cash_allocations.create!(general_account: clients, legal_entity: fondation, third_party: tiers, amount_cents: cents)
    Accounting::PostCashEntry.new(cash_entry: entry.reload).run!
    entry.cash_allocations.sole
  end

  def rattacher(entry, **attributs)
    service = described_class.new(journal_entry: entry, attributes: attributs)
    service.run!
    service
  end

  it "met la facture au registre en pointant l'écriture reprise, sans en passer une autre" do
    entry = reprise("2026-100", 30_559, tva: 1_730)

    expect { rattacher(entry) }.not_to change(JournalEntry, :count)

    facture = SalesInvoice.sole
    expect(facture).to have_attributes(number: "2026-100", third_party: ekikrok, legal_entity: srl, total_cents: 30_559,
                                       issued_on: Date.new(2026, 10, 1), kind: "invoice", posting_mode: "on_issue",
                                       journal_entry: entry, status: "issued")
    expect(facture).to be_attached
    expect(facture.sales_invoice_lines.sole).to have_attributes(general_account: pains, amount_cents: 30_559, vat_cents: 1_730, vat_rate: 6)
  end

  it "retrouve l'écriture par sa référence au journal, la pièce reprise ou le numéro" do
    entry = reprise("2026-078", 37_350)

    expect(described_class.entries_for(legal_entity: srl, reference: entry.reference)).to eq([entry])
    expect(described_class.entries_for(legal_entity: srl, reference: "2026/#{entry.number}")).to eq([entry])
    expect(described_class.entries_for(legal_entity: srl, reference: "2026:VENTES:2026-078")).to eq([entry])
    expect(described_class.entries_for(legal_entity: srl, reference: "2026-078")).to eq([entry])
    expect(described_class.entries_for(legal_entity: srl, reference: "2026-07")).to be_empty
    expect(described_class.entries_for(legal_entity: fondation, reference: "2026-078")).to be_empty
  end

  it "rattache une écriture passée à la main, au tiers et au numéro donnés" do
    entry = Accounting::PostDocument.new(
      legal_entity: fondation, journal: "sales", entry_date: Date.new(2026, 9, 1), label: "Location salle Saint-Gilles",
      lines: [{ account: clients, debit_cents: 64_000, credit_cents: 0 }, { account: salles, debit_cents: 0, credit_cents: 64_000 }]
    ).run!

    expect { rattacher(entry) }.to raise_error(described_class::Refused, /numéro/)
    expect { rattacher(entry, number: "2026-047") }.to raise_error(described_class::Refused, /tiers|client/)

    facture = rattacher(entry, number: "2026-047", third_party_id: saint_gilles.id).invoice
    expect(facture).to have_attributes(third_party: saint_gilles, total_cents: 64_000, legal_entity: fondation)
  end

  it "relie l'encaissement qui cite le numéro, puis le seul du montant exact" do
    entry = Accounting::PostDocument.new(
      legal_entity: fondation, journal: "sales", entry_date: Date.new(2026, 9, 1), label: "2026-047 Saint-Gilles salle",
      lines: [{ account: clients, debit_cents: 100_000, credit_cents: 0, third_party: saint_gilles },
              { account: salles, debit_cents: 0, credit_cents: 100_000 }]
    ).run!
    acompte = encaissement(40_000, communication: "Acompte facture 2026-047")
    solde = encaissement(60_000)

    service = rattacher(entry)

    expect(service.linked_allocations).to contain_exactly(acompte)
    expect(service.invoice).to have_attributes(status: "issued", remaining_cents: 60_000)
    expect(solde.reload.document).to be_nil

    autre = Accounting::PostDocument.new(
      legal_entity: fondation, journal: "sales", entry_date: Date.new(2026, 9, 2), label: "2026-048 Saint-Gilles",
      lines: [{ account: clients, debit_cents: 60_000, credit_cents: 0, third_party: saint_gilles },
              { account: salles, debit_cents: 0, credit_cents: 60_000 }]
    ).run!
    expect(rattacher(autre).invoice).to have_attributes(status: "paid", paid_on: Date.new(2026, 10, 10))
    expect(solde.reload.document.number).to eq("2026-048")
  end

  it "ne relie pas un virement qui peut payer deux ventes du même montant" do
    premiere = reprise("2026-086", 30_559, tiers: saint_gilles, entite: fondation)
    reprise("2026-100", 30_559, tiers: saint_gilles, entite: fondation)
    virement = encaissement(30_559)

    service = rattacher(premiere)

    expect(service.linked_allocations).to be_empty
    expect(service.warnings.join).to include("autre vente du même montant")
    expect(virement.reload.document).to be_nil
  end

  it "refuse une écriture déjà rattachée, contre-passée ou d'un autre journal" do
    entry = reprise("2026-100", 10_000)
    rattacher(entry)
    expect { rattacher(entry) }.to raise_error(described_class::Refused, /déjà celle de la facture 2026-100/)

    contre = reprise("2026-101", 10_000)
    Accounting::ReverseEntry.new(journal_entry: contre, entry_date: contre.entry_date).run!
    expect { rattacher(contre) }.to raise_error(described_class::Refused, /contre-passée/)
  end

  it "refuse un montant ou un tiers qui contredit l'écriture" do
    entry = reprise("2026-100", 10_000)

    expect { rattacher(entry, total_cents: 12_000) }.to raise_error(described_class::Refused, /porte 100 €/)
    expect { rattacher(entry, third_party_id: saint_gilles.id) }.to raise_error(described_class::Refused, /sur Ekikrok/)
  end

  it "se retire sans toucher au grand livre, et rend ses encaissements au 400000" do
    entry = Accounting::PostDocument.new(
      legal_entity: fondation, journal: "sales", entry_date: Date.new(2026, 9, 1), label: "2026-047",
      lines: [{ account: clients, debit_cents: 40_000, credit_cents: 0, third_party: saint_gilles },
              { account: salles, debit_cents: 0, credit_cents: 40_000 }]
    ).run!
    virement = encaissement(40_000)
    facture = rattacher(entry).invoice
    expect(facture.reload).to be_paid

    expect { SalesInvoices::Withdraw.new(sales_invoice: facture).run! }.not_to change(JournalEntry, :count)
    expect(SalesInvoice.find_by(id: facture.id)).to be_nil
    expect(virement.reload.document).to be_nil
  end

  it "refuse de corriger ce qui fait l'écriture, accepte une note" do
    facture = rattacher(reprise("2026-100", 10_000)).invoice

    expect do
      SalesInvoices::Correct.new(sales_invoice: facture, attributes: { "number" => "2026-200" }).run!
    end.to raise_error(SalesInvoices::Correct::Refused, /écriture reprise/)

    SalesInvoices::Correct.new(sales_invoice: facture.reload, attributes: { "notes" => "Relancé" }).run!
    expect(facture.reload.notes).to eq("Relancé")
  end
end
