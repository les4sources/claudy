require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Toute facture de vente au registre (Michael, 2026-10-30) : sans réservation,
# un tiers et des lignes, et l'écriture au journal Ventes ; une correction
# contre-passe et repasse ; une note de crédit inverse l'écriture et réduit le
# reste dû de la facture qu'elle corrige.
RSpec.describe "Factures de vente sans réservation" do
  include FinanceBuilders

  let!(:srl) { build_legal_entity(name: "Domaine d'Ahinvaux SRL", form: "srl").tap { |e| e.update!(vat_regime: "subject") } }
  let!(:fondation) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:exercice_srl) { build_fiscal_year(srl) }
  let!(:exercice_fondation) { build_fiscal_year(fondation) }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4, nature: "asset") }
  let!(:tva_due) { build_general_account(code: "451000", name: "TVA à payer", klass: 4, nature: "liability") }
  let!(:prestations) { build_general_account(code: "706000", name: "Prestations de services", klass: 7, nature: "revenue") }
  let!(:locations) { build_general_account(code: "701002", name: "Location de salles", klass: 7, nature: "revenue") }
  let!(:fabry) { ThirdParty.create!(name: "Fabry", kind: "customer") }

  def enregistrer(entite: srl, numero: "2026-047", lignes: [{ general_account_id: prestations.id, net_cents: 100_000, vat_rate: 21 }],
                  total: 121_000, **autres)
    SalesInvoices::Record.new(attributes: { legal_entity_id: entite.id, third_party_id: fabry.id, number: numero,
                                            issued_on: Date.new(2026, 10, 1), total_cents: total,
                                            sales_invoice_lines_attributes: lignes }.merge(autres)).run!
  end

  def lignes_de(entry)
    entry.journal_lines.map { |l| [l.general_account.code, l.debit_cents, l.credit_cents] }.sort
  end

  describe "l'enregistrement" do
    it "passe l'écriture au journal Ventes : 400000 sur le tiers, produit HTVA et 451000 pour une entité assujettie" do
      facture = enregistrer

      entry = facture.journal_entry
      expect(entry.journal).to eq("sales")
      expect(entry.entry_date).to eq(Date.new(2026, 10, 1))
      expect(lignes_de(entry)).to eq([["400000", 121_000, 0], ["451000", 0, 21_000], ["706000", 0, 100_000]])
      expect(entry.journal_lines.find { |l| l.general_account == clients }.third_party).to eq(fabry)
      expect(facture).to have_attributes(posting_mode: "on_issue", status: "issued", remaining_cents: 121_000)
      expect(facture.posted_at).to be_present
    end

    it "met tout au produit TTC pour la fondation, exemptée" do
      facture = enregistrer(entite: fondation, lignes: [{ general_account_id: locations.id, net_cents: 29_000, vat_rate: 0 }],
                            total: 29_000)

      expect(lignes_de(facture.journal_entry)).to eq([["400000", 29_000, 0], ["701002", 0, 29_000]])
    end

    it "refuse de la TVA sur une facture de la fondation" do
      expect { enregistrer(entite: fondation) }.to raise_error(ActiveRecord::RecordInvalid, /pas assujettie/)
    end

    it "exige un tiers et des lignes qui font le total" do
      expect do
        SalesInvoices::Record.new(attributes: { legal_entity_id: srl.id, number: "X", issued_on: Date.current,
                                                total_cents: 1_000 }).run!
      end.to raise_error(ActiveRecord::RecordInvalid, /tiers|ligne/i)

      expect { enregistrer(total: 120_000) }.to raise_error(ActiveRecord::RecordInvalid, /Les lignes font/)
      expect(SalesInvoice.count).to eq(0)
      expect(JournalEntry.count).to eq(0)
    end

    it "garde la TVA affichée par la facture plutôt que l'arrondi de Claudy" do
      facture = enregistrer(lignes: [{ general_account_id: prestations.id, net_cents: 100_000, vat_rate: 21, typed_vat_cents: 20_999 }],
                            total: 120_999)

      expect(facture.sales_invoice_lines.first).to have_attributes(vat_cents: 20_999, amount_cents: 120_999)
    end

    it "refuse un mois arrêté" do
      MonthClosing.create!(period_month: Date.new(2026, 10, 1), closed_at: Time.current)

      expect { enregistrer }.to raise_error(Accounting::PostSalesInvoice::NotPostable, /arrêté/)
      expect(SalesInvoice.count).to eq(0)
    end

    it "ne passe aucune écriture pour la facture d'un séjour (circuit d'encaissement)" do
      customer = Customer.create!(first_name: "Camille", last_name: "Renard", email: "camille@example.org")
      stay = Stay.create!(customer: customer, arrival_date: Date.new(2026, 6, 1), departure_date: Date.new(2026, 6, 4),
                          total_amount_cents: 130_000, invoice_status: "requested")

      service = SalesInvoices::Register.new(source: stay, legal_entity: fondation, number: "2026-007",
                                            issued_on: Date.new(2026, 6, 10), total_cents: 130_000)
      service.run!

      expect(service.invoice.posting_mode).to eq("on_payment")
      expect(JournalEntry.count).to eq(0)
    end
  end

  describe "la correction" do
    it "contre-passe à sa date et repasse quand les lignes changent" do
      facture = enregistrer
      ancienne = facture.journal_entry

      SalesInvoices::Correct.new(sales_invoice: facture, attributes: {
                                   "total_cents" => 60_500,
                                   "sales_invoice_lines_attributes" => [
                                     { "id" => facture.sales_invoice_lines.first.id, "net_cents" => 50_000, "vat_rate" => 21 }
                                   ]
                                 }).run!

      facture.reload
      expect(JournalEntry.where(reversal_of: ancienne).pluck(:entry_date)).to eq([Date.new(2026, 10, 1)])
      expect(facture.journal_entry).not_to eq(ancienne)
      expect(lignes_de(facture.journal_entry)).to eq([["400000", 60_500, 0], ["451000", 0, 10_500], ["706000", 0, 50_000]])
    end

    it "ne touche pas au grand livre pour une note" do
      facture = enregistrer

      expect do
        SalesInvoices::Correct.new(sales_invoice: facture, attributes: { "notes" => "Relancé le 15/10" }).run!
      end.not_to change(JournalEntry, :count)
    end

    it "refuse sur un mois arrêté et renvoie à la note de crédit" do
      facture = enregistrer
      MonthClosing.create!(period_month: Date.new(2026, 10, 1), closed_at: Time.current)

      expect do
        SalesInvoices::Correct.new(sales_invoice: facture, attributes: { "number" => "2026-048" }).run!
      end.to raise_error(SalesInvoices::Unpost::Refused, /note de crédit/)
      expect(facture.reload.number).to eq("2026-047")
    end

    it "refuse une modification en place d'une facture comptabilisée" do
      facture = enregistrer

      expect(facture.update(number: "2026-099")).to be(false)
      expect(facture.errors.full_messages.to_sentence).to include("contre-passation")
    end
  end

  describe "la note de crédit" do
    it "passe l'écriture inverse et solde la facture qu'elle corrige" do
      facture = enregistrer
      note = enregistrer(numero: "2026-062", kind: "credit_note", credited_invoice_id: facture.id)

      expect(lignes_de(note.journal_entry)).to eq([["400000", 0, 121_000], ["451000", 21_000, 0], ["706000", 100_000, 0]])
      expect(note.reload).to have_attributes(status: "paid", status_label: "Imputée")
      expect(facture.reload).to have_attributes(status: "paid", remaining_cents: 0)
    end

    it "réduit seulement le reste dû quand elle est partielle" do
      facture = enregistrer
      enregistrer(numero: "2026-062", kind: "credit_note", credited_invoice_id: facture.id,
                  lignes: [{ general_account_id: prestations.id, net_cents: 10_000, vat_rate: 21 }], total: 12_100)

      expect(facture.reload).to have_attributes(status: "issued", remaining_cents: 108_900)
    end
  end

  describe "le retrait" do
    it "contre-passe l'écriture et sort la facture du registre" do
      facture = enregistrer
      entry = facture.journal_entry

      SalesInvoices::Withdraw.new(sales_invoice: facture).run!

      expect(SalesInvoice.find_by(id: facture.id)).to be_nil
      expect(JournalEntry.where(reversal_of: entry)).to exist
    end

    it "refuse tant qu'une note de crédit la corrige" do
      facture = enregistrer
      enregistrer(numero: "2026-062", kind: "credit_note", credited_invoice_id: facture.id)

      expect { SalesInvoices::Withdraw.new(sales_invoice: facture).run! }
        .to raise_error(SalesInvoices::Withdraw::Refused, /note de crédit/)
    end
  end
end
