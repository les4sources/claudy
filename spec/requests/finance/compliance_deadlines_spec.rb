require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# L'échéancier comptable — ex-base Notion « Échéancier comptable ».
RSpec.describe "Comptabilité > Échéancier", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-echeancier@les4sources.be", password: "password123") }
  let!(:srl) { build_legal_entity(name: "SRL de test", form: "srl") }
  let!(:ssi) { build_legal_entity(name: "Société simple de test", form: "simple_company") }
  let!(:fiscal_year) { build_fiscal_year(ssi) }
  let!(:charges) { build_general_account(code: "640000", name: "Impôts", klass: 6, nature: "expense") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:receveur) { ThirdParty.create!(name: "SPF Finances", kind: "supplier", iban: "BE68539007547034") }

  let!(:tva) do
    ComplianceObligation.create!(title: "Déclaration TVA", legal_entity: srl, frequency: "quarterly",
                                 first_due_on: Date.current - 10)
  end
  let!(:precompte) do
    ComplianceObligation.create!(title: "Précompte immobilier", legal_entity: ssi, frequency: "yearly",
                                 covers: "current", payment: true, first_due_on: Date.current + 14)
  end

  before do
    sign_in user
    ComplianceDeadlines::Generate.new.run!
  end

  def deadline_of(obligation) = obligation.compliance_deadlines.ordered.first

  it "range le retard en tête, puis les trente prochains jours" do
    get finance_compliance_deadlines_path

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("En retard", "Dans les 30 jours", "Déclaration TVA", "Précompte immobilier")
    expect(body.index("Déclaration TVA")).to be < body.index("Précompte immobilier")
    expect(body).to include("subnav-accounting")
  end

  it "filtre par entité" do
    get finance_compliance_deadlines_path(entity: ssi.id)

    expect(response.body).to include("Précompte immobilier")
    expect(response.body).not_to include("Déclaration TVA —")
  end

  it "coche une échéance faite depuis la liste, et retient qui et quand" do
    deadline = deadline_of(tva)

    post close_finance_compliance_deadline_path(deadline, status: "done")

    deadline.reload
    expect(deadline.effective_status).to eq("done")
    expect(deadline.done_by_user).to eq(user)
    expect(deadline.done_on).to eq(Date.current)
  end

  it "rouvre une échéance close" do
    deadline = deadline_of(tva)
    deadline.close!(status: "not_applicable", user: user)

    post reopen_finance_compliance_deadline_path(deadline)

    expect(deadline.reload.status).to eq("todo")
    expect(deadline.done_on).to be_nil
  end

  it "reporte la date pour cette fois, et garde une note" do
    deadline = deadline_of(tva)

    patch finance_compliance_deadline_path(deadline),
          params: { compliance_deadline: { due_on: Date.current + 3, note: "Accord du comptable" } }

    expect(deadline.reload.due_on).to eq(Date.current + 3)
    expect(deadline.note).to eq("Accord du comptable")
  end

  it "affiche la fiche d'une échéance de paiement et propose d'encoder la facture" do
    get finance_compliance_deadline_path(deadline_of(precompte))

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Paiement", "Encoder la facture")
  end

  describe "le paiement se solde par sa facture" do
    let(:deadline) { deadline_of(precompte) }

    def encode_invoice
      post finance_purchase_invoices_path(compliance_deadline_id: deadline.id), params: {
        purchase_invoice: {
          legal_entity_id: ssi.id, third_party_id: receveur.id, number: "AER-2026",
          issued_on: Date.current, due_on: deadline.due_on, total_euros: "1234,00",
          purchase_invoice_lines_attributes: { "0" => { general_account_id: charges.id, amount_euros: "1234,00" } }
        }
      }
      PurchaseInvoice.find_by(number: "AER-2026")
    end

    it "l'annonce dans « À payer », hors total, tant que la pièce n'est pas encodée" do
      get finance_payables_path

      expect(response.body).to include("Paiements attendus", "Précompte immobilier —", "Rien à payer")
    end

    it "lie la facture encodée depuis l'échéance, qui entre alors dans « À payer » avec son badge" do
      invoice = encode_invoice

      expect(invoice).to be_present
      expect(deadline.reload.purchase_invoice).to eq(invoice)

      PurchaseInvoices::Advance.new(purchase_invoice: invoice).submit!
      get finance_payables_path

      expect(response.body).to include("échéancier : Précompte immobilier —", "SPF Finances")
      expect(response.body).not_to include("Paiements attendus")
    end

    it "refuse de cocher à la main une échéance qui attend sa facture" do
      invoice = encode_invoice

      post close_finance_compliance_deadline_path(deadline, status: "done")

      expect(deadline.reload.status).to eq("todo")
      expect(flash[:alert]).to include("se solde par sa facture")
      expect(invoice).to be_present
    end

    it "est faite dès que la facture est payée, sans case à cocher" do
      invoice = encode_invoice
      invoice.update_columns(status: "paid", paid_on: Date.current)

      expect(deadline.reload.effective_status).to eq("done")
      expect(ComplianceDeadline.outstanding).not_to include(deadline)
    end
  end

  describe "les obligations" do
    it "génère les échéances dès l'enregistrement d'une règle" do
      post finance_compliance_obligations_path, params: {
        compliance_obligation: { title: "Fiches 281.20", legal_entity_id: srl.id, frequency: "yearly",
                                 covers: "previous", first_due_on: Date.current + 60, active: "1" }
      }

      obligation = ComplianceObligation.find_by(title: "Fiches 281.20")
      expect(response).to redirect_to(finance_compliance_obligations_path)
      expect(obligation.compliance_deadlines.count).to eq(1)
    end

    it "liste les obligations par entité avec leur prochaine échéance" do
      get finance_compliance_obligations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("SRL de test", "Société simple de test", "Déclaration TVA")
    end
  end
end
