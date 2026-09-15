require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 3 — les emails de validation d'une facture d'achat.
# Aucun ne part vers un fournisseur : les membres du pôle, et la coordination
# comptable quand ça coince.
RSpec.describe PurchaseInvoiceMailer do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:antargaz) { ThirdParty.create!(name: "Antargaz", kind: "supplier", vat_number: "BE0123456789") }
  let!(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }

  let(:invoice) do
    facture = PurchaseInvoice.create!(legal_entity: entity, third_party: antargaz, number: "F-2026-42",
                                      issued_on: Date.new(2026, 6, 1), due_on: Date.new(2026, 6, 30),
                                      total_cents: 12_000, requires_validation: true,
                                      validation_team: technique, notes: "Livraison du 28 mai")
    facture.purchase_invoice_lines.create!(general_account: charges, team: technique,
                                           amount_cents: 12_000, label: "Gaz mai")
    facture.reload
  end

  describe "validation_requested" do
    subject(:mail) { described_class.validation_requested(invoice, "martin@les4sources.be") }

    it "nomme le fournisseur et le montant dans l'objet" do
      expect(mail.to).to eq(["martin@les4sources.be"])
      expect(mail.subject).to eq("À valider — Antargaz — 120 €")
    end

    it "porte le lien signé de validation, et pas l'identifiant de la facture" do
      body = mail.body.encoded

      expect(body).to include("/achats/valider/")
      # Le jeton, pas l'id : un lien devinable n'est pas un lien.
      expect(body).not_to include("/achats/valider/#{invoice.id}")
    end

    it "détaille la ventilation et renvoie aussi vers Claudy" do
      body = CGI.unescapeHTML(mail.body.encoded)

      expect(body).to include("Antargaz", "F-2026-42", "Pôle Technique", "Gaz mai")
      expect(body).to include("Livraison du 28 mai")
      expect(body).to include("/finance/purchases/#{invoice.id}")
    end

    it "annonce la double signature au-delà de 5 000 €" do
      invoice.update_columns(total_cents: 600_000)
      invoice.purchase_invoice_lines.first.update_columns(amount_cents: 600_000)

      body = CGI.unescapeHTML(described_class.validation_requested(invoice.reload, "martin@les4sources.be").body.encoded)

      expect(body).to include("deux signatures Triodos")
    end
  end

  describe "disputed" do
    subject(:mail) { described_class.disputed(invoice, "tresorerie@les4sources.be") }

    before { invoice.update_columns(status: "disputed", dispute_reason: "Montant différent du devis") }

    it "porte le motif, et va à la coordination comptable" do
      expect(mail.to).to eq(["tresorerie@les4sources.be"])
      expect(mail.subject).to eq("Facture contestée — Antargaz — 120 €")
      expect(CGI.unescapeHTML(mail.body.encoded)).to include("Montant différent du devis")
    end
  end
end
