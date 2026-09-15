require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #240, phase 3 — la validation d'une facture d'achat par son pôle.
#
# Le point de la phase : rendre VISIBLE un blocage qui était implicite. Une
# facture qui demande l'aval d'un pôle s'arrête à « À valider », ses membres
# reçoivent un lien, et tant que personne n'a répondu elle n'est pas payable.
RSpec.describe "Comptabilité > Achats — validation par le pôle", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders
  # La suite tourne en `queue_adapter :inline` : `deliver_later` livre tout de
  # suite, donc on regarde les livraisons plutôt que la file.
  include ActiveSupport::Testing::TimeHelpers

  before { ActionMailer::Base.deliveries.clear }

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:charges) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:antargaz) { ThirdParty.create!(name: "Antargaz", kind: "supplier", vat_number: "BE0123456789") }
  let!(:technique) { Team.create!(name: "Pôle Technique", kind: "economic") }

  # Le sourcier du pôle : un `Human` membre, et le `User` qui va avec.
  let!(:sourcier) { Human.create!(name: "Martin", email: "martin@les4sources.be", status: "active") }
  let!(:membership) { TeamMembership.create!(team: technique, human: sourcier) }
  let(:sourcier_user) { User.create!(email: "martin-user@les4sources.be", password: "password123", human: sourcier) }

  # Un compte sans membre rattaché : accueil générique / comptabilité.
  let(:compta) { User.create!(email: "compta@les4sources.be", password: "password123") }

  # Quelqu'un d'un autre pôle : il voit l'attente, il ne tranche pas.
  let!(:autre_human) { Human.create!(name: "Autre", email: "autre@les4sources.be", status: "active") }
  let(:autre_user) { User.create!(email: "autre-user@les4sources.be", password: "password123", human: autre_human) }

  def facture(status: nil, requires_validation: true, team: technique)
    invoice = PurchaseInvoice.create!(legal_entity: entity, third_party: antargaz, number: "F-#{rand(10_000)}",
                                      issued_on: Date.new(2026, 6, 1), total_cents: 12_000,
                                      requires_validation: requires_validation, validation_team: team)
    invoice.purchase_invoice_lines.create!(general_account: charges, team: technique, amount_cents: 12_000)
    invoice.update_column(:status, status) if status
    invoice.reload
  end

  describe "l'envoi en validation" do
    it "arrête la facture à « À valider » et prévient les membres du pôle" do
      invoice = facture
      sign_in compta

      post submit_finance_purchase_invoice_path(invoice)

      expect(ActionMailer::Base.deliveries.map { |m| m.to }.flatten).to eq(["martin@les4sources.be"])
      expect(ActionMailer::Base.deliveries.last.subject).to include("À valider", "Antargaz")
      expect(invoice.reload.status).to eq("to_validate")
      # L'écriture ne naît PAS ici : une facture qui attend un aval n'est pas une dette.
      expect(JournalEntry.find_by(source: invoice, journal: "purchases")).to be_nil
      expect(flash[:notice]).to include("1 membre")
    end

    it "le dit franchement quand le pôle n'a aucune adresse" do
      muet = Team.create!(name: "Pôle Muet", kind: "economic")
      invoice = facture(team: muet)
      sign_in compta

      post submit_finance_purchase_invoice_path(invoice)

      expect(ActionMailer::Base.deliveries).to be_empty
      expect(invoice.reload.status).to eq("to_validate")
      expect(flash[:notice]).to include("aucune adresse")
    end
  end

  describe "le canal jeton (sans connexion)" do
    it "affiche la facture sans rien muter sur un GET" do
      invoice = facture(status: "to_validate")

      get finance_purchase_invoice_validation_path(invoice.validation_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Antargaz")
      expect(invoice.reload.status).to eq("to_validate")
      expect(invoice.validated_at).to be_nil
    end

    it "valide sur un POST, génère l'écriture, et trace la réponse" do
      invoice = facture(status: "to_validate")

      post finance_purchase_invoice_validation_confirm_path(invoice.validation_token)

      expect(response).to have_http_status(:ok)
      invoice.reload
      expect(invoice.status).to eq("to_pay")
      expect(invoice.validated_at).to be_present
      expect(JournalEntry.find_by(source: invoice, journal: "purchases")).to be_present
    end

    it "renvoie une page d'état, jamais un faux « merci », sur une facture déjà tranchée" do
      invoice = facture(status: "to_process")

      post finance_purchase_invoice_validation_confirm_path(invoice.validation_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("repartie en traitement")
      expect(invoice.reload.status).to eq("to_process")
    end

    it "refuse un jeton forgé ou émis pour autre chose" do
      invoice = facture(status: "to_validate")
      autre_portee = invoice.signed_id(purpose: :something_else, expires_in: 1.day)

      get finance_purchase_invoice_validation_path(autre_portee)
      expect(response).to have_http_status(:not_found)

      get finance_purchase_invoice_validation_path("n-importe-quoi")
      expect(response).to have_http_status(:not_found)
    end

    it "refuse un jeton expiré" do
      invoice = facture(status: "to_validate")
      token = invoice.validation_token

      travel_to(PurchaseInvoice::TOKEN_TTL.from_now + 1.day) do
        get finance_purchase_invoice_validation_path(token)
        expect(response).to have_http_status(:not_found)
      end
    end

    it "exige une connexion pour contester — un motif doit être attribuable" do
      invoice = facture(status: "to_validate")

      get finance_purchase_invoice_validation_dispute_path(invoice.validation_token)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "renvoie vers la fiche admin quand on est connecté" do
      invoice = facture(status: "to_validate")
      sign_in sourcier_user

      get finance_purchase_invoice_validation_dispute_path(invoice.validation_token)

      expect(response).to redirect_to(finance_purchase_invoice_path(invoice))
    end
  end

  describe "le canal admin" do
    it "laisse un membre du pôle valider" do
      invoice = facture(status: "to_validate")
      sign_in sourcier_user

      post validate_by_team_finance_purchase_invoice_path(invoice), params: { decision: "approve" }

      invoice.reload
      expect(invoice.status).to eq("to_pay")
      expect(invoice.validated_by).to eq(sourcier_user)
    end

    it "laisse un compte sans membre rattaché débloquer une facture que le pôle laisse dormir" do
      invoice = facture(status: "to_validate")
      sign_in compta

      post validate_by_team_finance_purchase_invoice_path(invoice), params: { decision: "approve" }

      expect(invoice.reload.status).to eq("to_pay")
    end

    it "refuse à quelqu'un d'un autre pôle" do
      invoice = facture(status: "to_validate")
      sign_in autre_user

      post validate_by_team_finance_purchase_invoice_path(invoice), params: { decision: "approve" }

      expect(invoice.reload.status).to eq("to_validate")
      expect(flash[:alert]).to include("Pôle Technique")
    end

    it "conteste avec un motif, et prévient la coordination comptable" do
      Setting.set("accounting_notification_emails", "tresorerie@les4sources.be")
      invoice = facture(status: "to_validate")
      sign_in sourcier_user

      post validate_by_team_finance_purchase_invoice_path(invoice),
           params: { decision: "reject", reason: "Le montant ne correspond pas au devis." }

      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to eq(["tresorerie@les4sources.be"])
      expect(ActionMailer::Base.deliveries.last.subject).to include("contestée")

      invoice.reload
      expect(invoice.status).to eq("disputed")
      expect(invoice.dispute_reason).to include("devis")
      expect(invoice.validated_by).to eq(sourcier_user)
      expect(invoice.validated_at).to be_nil
    end

    it "refuse une contestation sans motif" do
      invoice = facture(status: "to_validate")
      sign_in sourcier_user

      post validate_by_team_finance_purchase_invoice_path(invoice), params: { decision: "reject", reason: "" }

      expect(invoice.reload.status).to eq("to_validate")
      expect(flash[:alert]).to be_present
    end

    it "montre les boutons au membre du pôle, et seulement l'attente aux autres" do
      invoice = facture(status: "to_validate")

      sign_in sourcier_user
      get finance_purchase_invoice_path(invoice)
      expect(response.body).to include("Je valide cette facture")

      sign_out sourcier_user
      sign_in autre_user
      get finance_purchase_invoice_path(invoice)
      expect(response.body).not_to include("Je valide cette facture")
      expect(CGI.unescapeHTML(response.body)).to include("En attente du pôle Pôle Technique")
    end
  end

  describe "le callout de la page du pôle" do
    it "annonce les factures à valider, avec un lien filtré" do
      invoice = facture(status: "to_validate")
      sign_in compta

      get team_path(technique)

      body = CGI.unescapeHTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(body).to include("1 facture en attente de validation par ce pôle")
      expect(body).to include(finance_purchase_invoices_path(status: "to_validate", team_id: technique.id))
      expect(body).to include("Antargaz")
    end

    it "ne rend rien quand il n'y a rien à trancher" do
      facture(status: "to_process")
      sign_in compta

      get team_path(technique)

      expect(CGI.unescapeHTML(response.body)).not_to include("en attente de validation par ce pôle")
    end
  end
end
