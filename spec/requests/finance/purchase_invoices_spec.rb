require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 2 — les écrans Comptabilité > Achats.
RSpec.describe "Comptabilité > Achats", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:antargaz) { ThirdParty.create!(name: "Antargaz", kind: "supplier", vat_number: "BE0123456789") }
  let!(:luminus) { ThirdParty.create!(name: "Luminus", kind: "supplier") }
  let!(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }

  before { sign_in user }

  def cree_facture(tiers: antargaz, total: 12_000, number: "F-2026-1", ventile: true, status: nil)
    facture = PurchaseInvoice.create!(legal_entity: entity, third_party: tiers, number: number,
                                      issued_on: Date.new(2026, 6, 1), total_cents: total)
    facture.purchase_invoice_lines.create!(general_account: charges, team: technique, amount_cents: total) if ventile
    facture.update_column(:status, status) if status
    facture.reload
  end

  describe "GET /finance/purchases" do
    it "liste les factures avec leurs totaux par statut" do
      cree_facture
      cree_facture(tiers: luminus, total: 45_000, number: "L-9")

      get finance_purchase_invoices_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Antargaz", "Luminus")
      expect(response.body).to include("À traiter")
      expect(response.body).to include("570,00")
      expect(response.body).to include("subnav-accounting")
    end

    it "filtre par fournisseur" do
      cree_facture
      cree_facture(tiers: luminus, total: 45_000, number: "L-9")

      get finance_purchase_invoices_path(third_party_id: luminus.id)

      expect(response.body).to include("Luminus")
      expect(response.body).not_to match(%r{<div class="font-medium text-gray-900">Antargaz</div>})
    end

    it "filtre par pôle" do
      cree_facture
      autre = Team.create!(name: "Pôle Accueil", kind: "economic")

      get finance_purchase_invoices_path(team_id: autre.id)

      expect(response.body).to include("Aucune facture ne correspond")
    end

    it "filtre par période" do
      cree_facture

      get finance_purchase_invoices_path(from: "2026-07-01")

      expect(response.body).to include("Aucune facture ne correspond")
    end

    it "ne tombe pas sur une date illisible" do
      cree_facture

      get finance_purchase_invoices_path(from: "hier")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Antargaz")
    end
  end

  describe "POST /finance/purchases" do
    it "enregistre une facture et sa ventilation" do
      expect {
        post finance_purchase_invoices_path,
             params: { purchase_invoice: {
               legal_entity_id: entity.id, third_party_id: antargaz.id, number: "F-2026-9",
               issued_on: "2026-06-01", total_euros: "120,00",
               purchase_invoice_lines_attributes: {
                 "0" => { general_account_id: charges.id, team_id: technique.id,
                          amount_euros: "80,00", label: "Gaz" },
                 "1" => { general_account_id: charges.id, amount_euros: "40,00", label: "Location citerne" }
               }
             } }
      }.to change { PurchaseInvoice.count }.by(1)

      facture = PurchaseInvoice.last
      expect(facture.total_cents).to eq(12_000)
      expect(facture.purchase_invoice_lines.sum(&:amount_cents)).to eq(12_000)
      expect(facture.status).to eq("to_process")
    end

    it "refuse un numéro déjà vu chez le même fournisseur, en montrant l'existante" do
      existante = cree_facture

      expect {
        post finance_purchase_invoices_path,
             params: { purchase_invoice: { legal_entity_id: entity.id, third_party_id: antargaz.id,
                                           number: "F-2026-1", issued_on: "2026-07-01",
                                           total_euros: "50,00" } }
      }.not_to change { PurchaseInvoice.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Ce numéro existe déjà pour ce tiers")
      expect(response.body).to include(finance_purchase_invoice_path(existante))
    end
  end

  describe "GET /finance/purchases/:id" do
    it "montre la ventilation, le garde des 5 000 € et l'absence d'écriture" do
      facture = cree_facture(total: 600_000)

      get finance_purchase_invoice_path(facture)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Double signature Triodos requise")
      expect(response.body).to include("Pôle Technique")
      expect(response.body).to include("Envoyer au paiement")
    end

    it "signale un fournisseur sans numéro de TVA" do
      facture = cree_facture(tiers: luminus, number: "L-1")

      get finance_purchase_invoice_path(facture)

      expect(response.body).to include("TVA manquante")
    end
  end

  describe "POST /finance/purchases/:id/submit" do
    it "comptabilise et redirige avec un message" do
      facture = cree_facture

      expect {
        post submit_finance_purchase_invoice_path(facture)
      }.to change { JournalEntry.count }.by(1)

      expect(facture.reload.status).to eq("to_pay")
      follow_redirect!
      expect(response.body).to include("journal des achats")
    end

    it "refuse une facture mal ventilée sans rien écrire" do
      facture = cree_facture(ventile: false)

      expect {
        post submit_finance_purchase_invoice_path(facture)
      }.not_to change { JournalEntry.count }

      follow_redirect!
      expect(response.body).to include("à ventiler")
    end
  end

  describe "la contestation" do
    it "exige un motif" do
      facture = cree_facture

      post dispute_finance_purchase_invoice_path(facture), params: { reason: "" }

      expect(facture.reload.status).to eq("to_process")
    end

    it "bloque la facture avec son motif, et la rouvre" do
      facture = cree_facture

      post dispute_finance_purchase_invoice_path(facture), params: { reason: "Livraison jamais reçue" }
      expect(facture.reload.status).to eq("disputed")

      post reopen_finance_purchase_invoice_path(facture)
      expect(facture.reload.status).to eq("to_process")
    end
  end

  describe "une facture comptabilisée" do
    it "ne se modifie plus" do
      facture = cree_facture
      post submit_finance_purchase_invoice_path(facture)

      get edit_finance_purchase_invoice_path(facture)

      expect(response).to redirect_to(finance_purchase_invoice_path(facture))
      follow_redirect!
      expect(response.body).to include("contre-passation")
    end
  end
end
