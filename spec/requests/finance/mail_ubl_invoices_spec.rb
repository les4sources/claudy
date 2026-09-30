require "rails_helper"
require Rails.root.join("spec/support/finance_builders")
require Rails.root.join("spec/support/mail_intake_helpers")

# Encoder une facture électronique UBL reçue sur compta@ (2026-09-30).
RSpec.describe "Comptabilité > Boite de réception — factures UBL", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "tresoriere@les4sources.be", password: "password123") }
  let!(:entity) { LegalEntity.create!(name: "Fondation Les 4 Sources", form: "foundation", vat_number: "BE0508977707") }
  let!(:bruyerre) { ThirdParty.create!(name: "Bruyerre", kind: "supplier", vat_number: "BE0431703151") }
  let(:account) { MailAccount.create!(address: "compta@les4sources.be", purpose: "accounting") }
  let(:pdf) { text_pdf(["BRUYERRE", "Facture WIE45/2026/11492"]) }

  before { sign_in user }

  def relever_et_analyser(*raws)
    imap = MailIntakeHelpers::FakeImap.new(raws.each_with_index.to_h { |raw, i| [i + 1, raw] })
    MailIntake::Sync.new(mail_account: account, imap: imap).run!.each do |message|
      MailIntake::Analyze.new(mail_message: message, jev: MailIntakeHelpers::FakeJev.new(configured: false)).run!
    end
  end

  def piece_ubl(message) = message.mail_attachments.find_by(content_type: "application/pdf")

  it "pré-remplit une ligne de ventilation par taux de TVA, au montant TVAC" do
    xml = ubl_xml(taux: [[0, "100.00", "0.00"], [6, "300.00", "18.00"]], total: "418.00", pdf: pdf)
    message = relever_et_analyser(raw_ubl_mail(message_id: "a@okioki.be", xml: xml)).first

    get new_finance_purchase_invoice_path(mail_attachment_id: piece_ubl(message).id)

    body = response.body
    expect(body).to include(%(<option selected="selected" value="#{bruyerre.id}">Bruyerre</option>))
    expect(body).to include('value="TVA 0 %"', 'value="100.00"', 'value="TVA 6 %"', 'value="318.00"', 'value="418.00"')
    expect(body).not_to include("Payée d&#39;avance")
  end

  it "ne crée pas de ligne pour un taux déclaré à zéro euro" do
    xml = ubl_xml(taux: [[0, "0.00", "0.00"], [6, "392.51", "23.55"]], total: "416.06", pdf: pdf)
    message = relever_et_analyser(raw_ubl_mail(message_id: "z@okioki.be", xml: xml)).first

    get new_finance_purchase_invoice_path(mail_attachment_id: piece_ubl(message).id)

    expect(response.body).not_to include('value="TVA 0 %"')
    expect(response.body).to include('value="TVA 6 %"', 'value="416.06"')
  end

it "pré-remplit la communication, l'enregistre, et « À payer » la propose à copier" do
  xml = ubl_xml(payment_id: "+++000/0024/11862+++", pdf: pdf)
  message = relever_et_analyser(raw_ubl_mail(message_id: "comm@okioki.be", xml: xml)).first

  get new_finance_purchase_invoice_path(mail_attachment_id: piece_ubl(message).id)
  expect(response.body).to include('value="+++000/0024/11862+++"')

  post finance_purchase_invoices_path(mail_attachment_id: piece_ubl(message).id), params: {
    purchase_invoice: { legal_entity_id: entity.id, third_party_id: bruyerre.id, number: "WIE45/2026/11492",
                        issued_on: "2026-09-18", total_euros: "278.95", payment_reference: "000002411862" }
  }
  invoice = PurchaseInvoice.last
  expect(invoice.payment_reference).to eq("+++000/0024/11862+++")
  expect(invoice.payable_communication).to eq("+++000/0024/11862+++")
end

  it "note qu'une facture est déjà payée quand l'UBL le dit" do
    message = relever_et_analyser(raw_ubl_mail(message_id: "b@okioki.be", xml: ubl_xml(prepaid: "278.95", payable: "0.00", pdf: pdf))).first

    get finance_mail_message_path(message)
    expect(response.body).to include("Déjà payée selon la facture électronique", "facture électronique")

    get new_finance_purchase_invoice_path(mail_attachment_id: piece_ubl(message).id)
    expect(response.body).to include("Payée d&#39;avance selon la facture électronique (UBL).")
  end

  it "classe aussi le mail jumeau (le PDF envoyé avant l'UBL) quand la facture est encodée" do
    jumeau_pdf = text_pdf(["BRUYERRE TVA BE 0431.703.151", "Facture n° WIE45/2026/11492", "Total 278,95"])
    pdf_mail, ubl_mail = relever_et_analyser(
      raw_mail(message_id: "pdf@okioki.be", subject: "Vous avez reçu une facture électronique - BRUYERRE", pdf: jumeau_pdf),
      raw_ubl_mail(message_id: "ubl@okioki.be", xml: ubl_xml(pdf: pdf))
    )
    pdf_mail.mail_attachments.first.update!(proposal: {
                                               "kind" => { "value" => "invoice", "source" => "jev", "confidence" => 1.0 },
                                               "number" => { "value" => "WIE45/2026/11492", "source" => "jev", "confidence" => 1.0 },
                                               "supplier_vat" => { "value" => "BE0431703151", "source" => "code" }
                                             })

    post finance_purchase_invoices_path(mail_attachment_id: piece_ubl(ubl_mail).id), params: {
      purchase_invoice: { legal_entity_id: entity.id, third_party_id: bruyerre.id, number: "WIE45/2026/11492",
                          issued_on: "2026-09-18", total_euros: "278.95" }
    }

    invoice = PurchaseInvoice.last
    expect(ubl_mail.reload.status).to eq("filed")
    expect(pdf_mail.reload.status).to eq("filed")
    expect(pdf_mail.mail_attachments.first.purchase_invoice).to eq(invoice)
  end

  it "reconnaît aussi un jumeau dont la lecture a raté le fournisseur, par numéro, total et date" do
    pdf_mail, ubl_mail = relever_et_analyser(
      raw_mail(message_id: "pdf2@okioki.be", subject: "Facture septembre", pdf: text_pdf(["Facture 009-2026"])),
      raw_ubl_mail(message_id: "ubl2@okioki.be", xml: ubl_xml(number: "009-2026", pdf: pdf))
    )
    pdf_mail.mail_attachments.first.update!(proposal: {
                                               "number" => { "value" => "009-2026", "source" => "jev", "confidence" => 1.0 },
                                               "total_cents" => { "value" => 27_895, "source" => "jev", "confidence" => 1.0 },
                                               "issued_on" => { "value" => "2026-09-18", "source" => "jev", "confidence" => 1.0 },
                                               "supplier_vat" => { "value" => "BE0473670669", "source" => "code" }
                                             })

    post finance_purchase_invoices_path(mail_attachment_id: piece_ubl(ubl_mail).id), params: {
      purchase_invoice: { legal_entity_id: entity.id, third_party_id: bruyerre.id, number: "009-2026",
                          issued_on: "2026-09-18", total_euros: "278.95" }
    }

    expect(pdf_mail.reload.status).to eq("filed")
  end
end
