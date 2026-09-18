require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 5 — le justificatif mensuel des frais Stripe.
#
# Ce document ne crée AUCUNE écriture : les frais sont déjà comptabilisés par la
# ventilation des versements. Il archive la pièce qu'un contrôle réclame et
# affiche l'écart avec ce que Claudy a compté — affiché, jamais corrigé d'office.
RSpec.describe "Finances > Justificatifs Stripe (epic #240, phase 5)", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-stripe@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let(:stripe_general) { build_general_account(code: "551000", name: "Stripe") }
  let!(:cash_account) do
    CashAccount.create!(name: "Stripe", kind: "stripe", legal_entity: entity, general_account: stripe_general)
  end
  let(:month) { Date.current.beginning_of_month }

  before { sign_in user }

  def build_payout(fee_cents: 3_100, gross_cents: 130_000, on: Date.current)
    payout = StripePayout.create!(account_key: "claudy", cash_account: cash_account, stripe_id: "po_#{SecureRandom.hex(4)}",
                                  amount_cents: gross_cents - fee_cents, arrival_date: on)
    StripeBalanceTransaction.create!(stripe_payout: payout, stripe_id: "txn_#{SecureRandom.hex(4)}", kind: "charge",
                                     gross_cents: gross_cents, fee_cents: fee_cents, net_cents: gross_cents - fee_cents)
    payout
  end

  def pdf_upload
    Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 fake"), "application/pdf", original_filename: "stripe.pdf")
  end

  describe "le modèle" do
    it "ramène le mois à son premier jour" do
      invoice = StripeFeeInvoice.create!(account_key: "claudy", period_month: Date.new(2026, 3, 17))
      expect(invoice.period_month).to eq(Date.new(2026, 3, 1))
    end

    it "refuse un compte Stripe inconnu" do
      invoice = StripeFeeInvoice.new(account_key: "monopoly", period_month: month)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:account_key]).to be_present
    end

    it "refuse deux justificatifs pour le même compte et le même mois" do
      StripeFeeInvoice.create!(account_key: "claudy", period_month: month)
      doublon = StripeFeeInvoice.new(account_key: "claudy", period_month: month)
      expect(doublon).not_to be_valid
      expect(doublon.errors[:period_month]).to be_present
    end

    it "laisse redéposer un justificatif retiré" do
      invoice = StripeFeeInvoice.create!(account_key: "claudy", period_month: month)
      invoice.soft_delete!(validate: false)
      expect(StripeFeeInvoice.new(account_key: "claudy", period_month: month)).to be_valid
    end

    it "calcule l'écart, et rien tant que rien n'est déclaré" do
      invoice = StripeFeeInvoice.new(account_key: "claudy", period_month: month)
      expect(invoice.gap_cents(3_100)).to be_nil

      invoice.declared_fee_cents = 3_250
      expect(invoice.gap_cents(3_100)).to eq(150)
    end
  end

  describe "la page Coût d'encaissement" do
    it "montre le mois, ce que Claudy a compté, et explique que rien n'est comptabilisé ici" do
      build_payout(fee_cents: 3_100)

      get finance_collection_cost_path(from: month, to: month.end_of_month)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Justificatifs Stripe")
      expect(response.body).to include("déjà comptabilisés")
      expect(response.body).to include("Déposer le justificatif")
      expect(response.body).to include(I18n.l(month, format: "%B %Y"))
    end

    it "n'affiche aucun mois vide" do
      get finance_collection_cost_path(from: month, to: month.end_of_month)
      expect(response.body).to include("aucun justificatif déposé")
    end
  end

  describe "le dépôt" do
    it "enregistre le PDF et le montant déclaré, en euros" do
      build_payout(fee_cents: 3_100)

      post finance_stripe_fee_invoices_path, params: {
        account_key: "claudy", period_month: month.to_s,
        stripe_fee_invoice: { declared_fee: "32.50", reference: "IN-2026-0007", document: pdf_upload }
      }

      invoice = StripeFeeInvoice.find_for("claudy", month)
      expect(invoice).to be_present
      expect(invoice.declared_fee_cents).to eq(3_250)
      expect(invoice.reference).to eq("IN-2026-0007")
      expect(invoice.document).to be_attached
    end

    it "affiche l'écart sans rien corriger" do
      build_payout(fee_cents: 3_100)
      post finance_stripe_fee_invoices_path, params: {
        account_key: "claudy", period_month: month.to_s,
        stripe_fee_invoice: { declared_fee: "32.50", document: pdf_upload }
      }

      get finance_collection_cost_path(from: month, to: month.end_of_month)
      expect(response.body).to include("1,50 €")
      # Rien n'a bougé du côté de ce que Claudy a compté.
      expect(StripeBalanceTransaction.sum(:fee_cents)).to eq(3_100)
      expect(response.body).to include("Voir le PDF")
    end

    it "dit « identique » quand les deux chiffres coïncident" do
      build_payout(fee_cents: 3_100)
      post finance_stripe_fee_invoices_path, params: {
        account_key: "claudy", period_month: month.to_s,
        stripe_fee_invoice: { declared_fee: "31.00", document: pdf_upload }
      }

      get finance_collection_cost_path(from: month, to: month.end_of_month)
      expect(response.body).to include("identique")
    end

    it "met à jour le justificatif d'un mois déjà déposé plutôt que d'en créer un second" do
      build_payout(fee_cents: 3_100)
      2.times do |i|
        post finance_stripe_fee_invoices_path, params: {
          account_key: "claudy", period_month: month.to_s,
          stripe_fee_invoice: { declared_fee: "3#{i}.00", document: pdf_upload }
        }
      end

      expect(StripeFeeInvoice.for_account("claudy").for_month(month).count).to eq(1)
      expect(StripeFeeInvoice.find_for("claudy", month).declared_fee_cents).to eq(3_100)
    end
  end

  describe "le retrait" do
    it "détache le justificatif du mois sans rien détruire" do
      build_payout(fee_cents: 3_100)
      post finance_stripe_fee_invoices_path, params: {
        account_key: "claudy", period_month: month.to_s,
        stripe_fee_invoice: { declared_fee: "32.50", document: pdf_upload }
      }
      invoice = StripeFeeInvoice.find_for("claudy", month)

      delete finance_stripe_fee_invoice_path(invoice)

      expect(StripeFeeInvoice.find_by(id: invoice.id)).to be_nil
      expect(StripeFeeInvoice.unscoped.find(invoice.id).deleted_at).to be_present
    end
  end

  describe "aucune écriture" do
    it "ne crée pas la moindre écriture comptable" do
      build_payout(fee_cents: 3_100)

      expect {
        post finance_stripe_fee_invoices_path, params: {
          account_key: "claudy", period_month: month.to_s,
          stripe_fee_invoice: { declared_fee: "32.50", document: pdf_upload }
        }
      }.not_to change { AccountEntry.count }
    end
  end
end
