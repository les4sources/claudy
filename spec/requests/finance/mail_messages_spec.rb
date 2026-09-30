require "rails_helper"
require Rails.root.join("spec/support/finance_builders")
require Rails.root.join("spec/support/mail_intake_helpers")

# Messagerie, phase 1 — Comptabilité > Pièces reçues.
RSpec.describe "Comptabilité > Pièces reçues", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "tresoriere@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:proximus) { ThirdParty.create!(name: "Proximus", kind: "supplier") }
  let(:account) { MailAccount.create!(address: "compta@les4sources.be", purpose: "accounting") }
  let(:pdf) { text_pdf(["Facture 2026-77812", "Total 84,12"]) }
  let(:message) do
    imap = MailIntakeHelpers::FakeImap.new({ 1 => raw_mail(message_id: "x@proximus.be", pdf: pdf) })
    MailIntake::Sync.new(mail_account: account, imap: imap).run!.first
  end
  let(:attachment) do
    message.mail_attachments.first.tap do |a|
      a.update!(proposal: {
                  "kind" => { "value" => "invoice", "source" => "jev", "confidence" => 0.97 },
                  "third_party_id" => { "value" => proximus.id, "source" => "code" },
                  "legal_entity_id" => { "value" => entity.id, "source" => "code" },
                  "total_cents" => { "value" => 8_412, "source" => "jev", "confidence" => 0.93, "raw" => "84,12" },
                  "number" => { "value" => "2026-77812", "source" => "jev", "confidence" => 0.95 },
                  "issued_on" => { "value" => "2026-09-12", "source" => "jev", "confidence" => 0.9 },
                  "due_on" => { "value" => "2026-10-15", "source" => "jev", "confidence" => 0.6 }
                })
    end
  end

  before { sign_in user }

  it "liste la file avec ce qui est déjà reconnu" do
    attachment

    get finance_mail_messages_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pièces reçues", "Proximus", "Votre facture", "Facture · Proximus · 84,12")
  end

  it "montre la proposition, le PDF et l'action « Créer la facture »" do
    attachment

    get finance_mail_message_path(message)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("2026-77812", "reconnu", "à vérifier", "Créer la facture", "<iframe")
  end

  it "préremplit la facture depuis la pièce, PDF compris" do
    get new_finance_purchase_invoice_path(mail_attachment_id: attachment.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pré-remplie depuis le mail", 'value="2026-77812"', 'value="84.12"',
                                     'value="2026-10-15"', "facture.pdf")
    expect(response.body).to include("mail_attachment_id=#{attachment.id}")
  end

  it "à l'enregistrement, relie la pièce à sa facture, reprend le PDF et classe le mail" do
    post finance_purchase_invoices_path(mail_attachment_id: attachment.id), params: {
      purchase_invoice: { legal_entity_id: entity.id, third_party_id: proximus.id, number: "2026-77812",
                          issued_on: "2026-09-12", total_euros: "84,12" }
    }

    invoice = PurchaseInvoice.last
    expect(response).to redirect_to(finance_purchase_invoice_path(invoice))
    expect(invoice.document).to be_attached
    expect(invoice.pdf_sha256).to eq(attachment.sha256)
    expect(attachment.reload.purchase_invoice).to eq(invoice)
    expect(message.reload).to have_attributes(status: "filed", handled_by: user)
  end

  it "signale une pièce déjà encodée au lieu de proposer une seconde facture" do
    PurchaseInvoice.create!(legal_entity: entity, third_party: proximus, number: "X", issued_on: Date.current,
                            total_cents: 8_412, pdf_sha256: attachment.sha256)

    get finance_mail_message_path(message)

    expect(response.body).to include("Déjà dans la compta")
    expect(response.body).not_to include("Créer la facture")
  end

  it "« Ignorer » sort le mail de la file sans le supprimer, et garde qui" do
    post ignore_finance_mail_message_path(message)

    expect(message.reload).to have_attributes(status: "ignored", handled_by: user)
    get finance_mail_messages_path
    expect(response.body).not_to include("Votre facture")
    get finance_mail_messages_path(status: "ignored")
    expect(response.body).to include("Votre facture")
  end
end
