require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# « Déjà réglée » à l'encodage (Michael, 2026-11-12) : domiciliation, carte,
# virement déjà fait, billets. La facture le DIT, sans cocher « Payée » : le
# paiement reste un rapprochement, mais elle ne part pas dans « À payer » pour
# être payée une seconde fois.
RSpec.describe "Facture d'achat déjà réglée à l'encodage" do
  include FinanceBuilders

  let!(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:compte_banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:compte_caisse) { build_general_account(code: "570000", name: "Caisse") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:banque) { build_cash_account(entity, compte_banque) }
  let!(:voo) { ThirdParty.create!(name: "VOO", kind: "supplier") }

  def facture(settled_via: nil, settled_on: nil, total: 5_999)
    f = PurchaseInvoice.create!(legal_entity: entity, third_party: voo, number: "V-#{SecureRandom.hex(3)}",
                                issued_on: Date.new(2026, 10, 1), due_on: Date.new(2026, 10, 15), total_cents: total,
                                settled_via: settled_via, settled_on: settled_on)
    f.purchase_invoice_lines.create!(general_account: charges, amount_cents: total)
    f.reload
  end

  describe "par la banque" do
    it "prend la date de la pièce quand on n'en donne pas" do
      expect(facture(settled_via: "bank").settled_on).to eq(Date.new(2026, 10, 1))
    end

    it "se comptabilise mais ne rejoint ni « À payer » ni ses retards" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture(settled_via: "bank")).submit!

      expect(f).to be_to_pay
      expect(f).to be_posted
      expect(f).to be_awaiting_bank_line
      expect(f.status_label).to eq("Réglée, à rapprocher")
      expect(PurchaseInvoice.payable).not_to include(f)
      expect(PurchaseInvoice.awaiting_bank_line).to include(f)
      expect(Finance::PayableQueue.new.rows).not_to include(f)
      expect(f.overdue?(Date.new(2026, 11, 12))).to be(false)
    end

    it "passe « Payée » quand la ligne du relevé est rapprochée, et Claudy la propose" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture(settled_via: "bank", settled_on: Date.new(2026, 10, 3))).submit!
      ligne = build_cash_entry(banque, amount_cents: -5_999, entry_date: Date.new(2026, 10, 6), label: "Domiciliation VOO")

      expect(PurchaseInvoices::BankLineCandidates.new(f).entries).to eq([ligne])
      match = Finance::MatchPurchaseInvoices.new.for_entry(ligne).first
      expect(match.invoice).to eq(f)
      expect(match.confidence).to eq(Finance::MatchPurchaseInvoices::SETTLED_CONFIDENCE)

      Finance::RecordInvoicePayment.new(purchase_invoice: f, cash_entry: ligne).run!

      expect(f.reload).to be_paid
      expect(f.paid_on).to eq(Date.new(2026, 10, 6))
      expect(f.status_label).to eq("Payée")
    end

    it "ne propose pas une ligne déjà affectée, ni une autre structure, ni un autre montant" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture(settled_via: "bank")).submit!
      autre_entite = build_legal_entity(name: "SRL", form: "srl")
      build_cash_entry(build_cash_account(autre_entite, compte_banque, name: "Banque SRL"), amount_cents: -5_999,
                                                                                         entry_date: Date.new(2026, 10, 2))
      build_cash_entry(banque, amount_cents: -6_000, entry_date: Date.new(2026, 10, 2))
      prise = build_cash_entry(banque, amount_cents: -5_999, entry_date: Date.new(2026, 10, 2))
      allocate(prise, account: charges, amount_cents: -5_999, entity: entity)

      expect(PurchaseInvoices::BankLineCandidates.new(f).entries).to be_empty
    end

    it "se retire : la facture revient dans « À payer »" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture(settled_via: "bank")).submit!
      f.update!(settled_via: nil)

      expect(f.settled_on).to be_nil
      expect(PurchaseInvoice.payable).to include(f)
    end
  end

  # Domiciliation (Michael, 2026-11-12, la SWDE) : la banque prélèvera. Elle
  # reste due (« À payer », trésorerie), mais ne se vire pas.
  describe "par domiciliation" do
    it "prend l'échéance comme date de prélèvement, à défaut la date de la pièce" do
      expect(facture(settled_via: "direct_debit").settled_on).to eq(Date.new(2026, 10, 15))
      expect(facture(settled_via: "direct_debit", settled_on: Date.new(2026, 10, 20)).payable_due_on).to eq(Date.new(2026, 10, 20))
    end

    it "reste dans « À payer », jamais en retard, mais hors fichier de virements" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture(settled_via: "direct_debit")).submit!

      expect(f).to be_to_pay
      expect(f).to be_posted
      expect(f.status_label).to eq("Domiciliée")
      expect(f).to be_awaiting_direct_debit
      expect(f).not_to be_awaiting_bank_line
      expect(PurchaseInvoice.payable).to include(f)
      expect(Finance::PayableQueue.new.rows).to include(f)
      expect(f.payable_overdue?(Date.new(2026, 11, 12))).to be(false)
      expect(Finance::SepaCreditTransfer.problem_for(f)).to include("Domiciliation", "pas de virement")
    end

    it "propose la ligne du prélèvement et passe « Payée » au rapprochement" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture(settled_via: "direct_debit")).submit!
      ligne = build_cash_entry(banque, amount_cents: -5_999, entry_date: Date.new(2026, 10, 16), label: "Domiciliation SWDE")

      expect(PurchaseInvoices::BankLineCandidates.new(f).entries).to eq([ligne])
      match = Finance::MatchPurchaseInvoices.new.for_entry(ligne).first
      expect(match.invoice).to eq(f)
      expect(match.reason).to include("domiciliée")

      Finance::RecordInvoicePayment.new(purchase_invoice: f, cash_entry: ligne).run!

      expect(f.reload).to be_paid
      expect(f.status_label).to eq("Payée")
    end
  end

  # Compensation (Michael, 2026-11-12, loyer SSI #19) : éteinte avec d'autres
  # dettes, sans argent. Hors file et trésorerie, la dette reste au 440000.
  describe "par compensation" do
    it "sort de « À payer », du fichier SEPA et des suggestions de rapprochement" do
      f = PurchaseInvoices::Advance.new(purchase_invoice: facture(settled_via: "offset", settled_on: Date.new(2026, 10, 20))).submit!

      expect(f).to be_to_pay
      expect(f).to be_posted
      expect(f.status_label).to eq("Compensée, à justifier")
      expect(f).to be_awaiting_offset_entry
      expect(f).not_to be_expects_bank_line
      expect(PurchaseInvoice.payable).not_to include(f)
      expect(Finance::PayableQueue.new.rows).not_to include(f)
      expect(f.overdue?(Date.new(2026, 11, 12))).to be(false)
      expect(Finance::SepaCreditTransfer.problem_for(f)).to include("compensation")

      ligne = build_cash_entry(banque, amount_cents: -5_999, entry_date: Date.new(2026, 10, 21))
      expect(Finance::MatchPurchaseInvoices.new.for_entry(ligne).map(&:invoice)).not_to include(f)
      expect(PurchaseInvoices::BankLineCandidates.new(f).entries).to be_empty
    end
  end

  describe "en espèces" do
    let!(:caisse) { build_cash_account(entity, compte_caisse, name: "Caisse", kind: "cash") }

    it "crée la sortie de caisse à la comptabilisation, à la date du règlement" do
      service = PurchaseInvoices::Advance.new(purchase_invoice: facture(settled_via: "cash", settled_on: Date.new(2026, 10, 2)))
      f = nil
      expect { f = service.submit! }.to change(CashEntry, :count).by(1)

      expect(service.settlement_error).to be_nil
      expect(f).to be_paid
      expect(CashEntry.order(:id).last).to have_attributes(cash_account: caisse, amount_cents: -5_999,
                                                           entry_date: Date.new(2026, 10, 2))
    end

    it "laisse la facture « À payer » quand la caisse n'est pas désignable, sans défaire l'écriture" do
      build_cash_account(entity, compte_caisse, name: "Caisse bar", kind: "cash")
      service = PurchaseInvoices::Advance.new(purchase_invoice: facture(settled_via: "cash"))
      f = nil
      expect { f = service.submit! }.not_to change(CashEntry, :count)

      expect(service.settlement_error).to include("plusieurs caisses")
      expect(f).to be_to_pay
      expect(f).to be_posted
      expect(PurchaseInvoice.payable).to include(f)
    end
  end

  it "ne s'applique pas à une note de crédit" do
    note = PurchaseInvoice.create!(legal_entity: entity, third_party: voo, kind: "credit_note",
                                   issued_on: Date.new(2026, 10, 1), total_cents: 1_000, settled_via: "bank")

    expect(note.settled_via).to be_nil
  end
end
