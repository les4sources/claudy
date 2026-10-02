require "rails_helper"
require Rails.root.join("spec/support/mail_intake_helpers")

# Factures électroniques UBL (2026-09-30) : lire sans deviner.
RSpec.describe MailIntake::Ubl do
  let(:pdf) { text_pdf(["BRUYERRE", "Facture WIE45/2026/11492", "Total 278,95"]) }

  describe "lecture" do
    subject(:ubl) { described_class.new(ubl_xml(taux: [[0, "100.00", "0.00"], [6, "300.00", "18.00"]], total: "418.00", pdf: pdf)) }

    it "lit numéro, dates, fournisseur, client et montants tels quels" do
      expect(ubl).to have_attributes(number: "WIE45/2026/11492", issued_on: Date.new(2026, 9, 18),
                                     due_on: Date.new(2026, 10, 18), total_cents: 41_800, payable_cents: 41_800,
                                     payment_reference: "+++090/1234/56789+++", credit_note?: false)
      expect(ubl.supplier).to have_attributes(name: "BRUYERRE", vat: "BE0431703151", iban: "BE68539007547034")
      expect(ubl.customer.vat).to eq("BE0508977707")
    end

    it "donne la TVA par taux, et le PDF embarqué" do
      expect(ubl.tax_lines.map { |l| [l.percent, l.total_cents] }).to eq([[0.0, 10_000], [6.0, 31_800]])
      expect(ubl.embedded_pdf).to have_attributes(filename: "facture.pdf", content_type: "application/pdf", bytes: pdf)
    end

    it "sait qu'une facture est payée d'avance quand il ne reste rien à payer" do
      payee = described_class.new(ubl_xml(prepaid: "278.95", payable: "0.00"))
      expect(payee.fully_prepaid?).to be(true)
      expect(ubl.fully_prepaid?).to be(false)
    end

    it "reconnaît une UBL, et seulement une UBL" do
      expect(described_class.ubl?(ubl_xml)).to be(true)
      expect(described_class.ubl?("<factures><f/></factures>")).to be(false)
      expect(described_class.ubl?("pas du xml")).to be(false)
    end

    it "ne résout aucune entité externe (XXE)" do
      piege = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE Invoice [<!ENTITY secret SYSTEM "file:///etc/passwd">]>
        <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
                 xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
          <cbc:ID>&secret;</cbc:ID>
        </Invoice>
      XML
      expect(described_class.new(piege).number.to_s).not_to include("root:")
    end
  end

  describe "relève et analyse" do
    let!(:fondation) { LegalEntity.create!(name: "Fondation Les 4 Sources", form: "foundation", vat_number: "BE0508977707") }
    let(:account) { MailAccount.create!(address: "compta@les4sources.be", purpose: "accounting") }
    let(:jev) { MailIntakeHelpers::FakeJev.new }

    def relever(raws)
      imap = MailIntakeHelpers::FakeImap.new(raws.each_with_index.to_h { |raw, i| [i + 1, raw] })
      MailIntake::Sync.new(mail_account: account, imap: imap).run!
    end

    it "garde le XML et en extrait le PDF, relié à lui" do
      message = relever([raw_ubl_mail(message_id: "u1@okioki.be", xml: ubl_xml(pdf: pdf))]).first

      xml, embarque = message.mail_attachments.order(:id).to_a
      expect(xml).to have_attributes(content_type: "application/xml", embedded_in_id: nil)
      expect(embarque).to have_attributes(content_type: "application/pdf", filename: "facture.pdf", embedded_in_id: xml.id)
      expect(embarque.file.download).to eq(pdf)
    end

    it "ignore un XML qui n'est pas une facture UBL" do
      mail = Mail.new(raw_mail(message_id: "x@a.be"))
      mail.add_file(filename: "export.xml", content: "<export><ligne/></export>", mime_type: "text/xml")

      message = relever([mail.to_s]).first

      expect(message.mail_attachments).to be_empty
    end

    it "propose tout depuis l'UBL, sans poser une seule question à Jev" do
      message = relever([raw_ubl_mail(message_id: "u2@okioki.be", xml: ubl_xml(pdf: pdf))]).first

      MailIntake::Analyze.new(mail_message: message, jev: jev).run!

      piece = message.mail_attachments.find_by(content_type: "application/pdf")
      expect(jev.calls).to be_empty
      expect(piece).to be_from_ubl
      expect(piece.kind).to eq("invoice")
      expect(piece.proposal.transform_values { |v| v["value"] }).to include(
        "number" => "WIE45/2026/11492", "issued_on" => "2026-09-18", "due_on" => "2026-10-18",
        "total_cents" => 27_895, "legal_entity_id" => fondation.id, "supplier_name" => "BRUYERRE",
        "supplier_vat" => "BE0431703151", "supplier_iban" => "BE68539007547034"
      )
      expect(piece.proposal.values.map { |v| v["source"] }.uniq).to eq(["ubl"])
      expect(piece).to be_invoice_like
      expect(message.mail_attachments.find_by(content_type: "application/xml").kind).to eq("ubl_data")
      expect(message.reload.triage.dig("nature", "value")).to eq("invoice")
    end

    it "reprend la communication structurée de l'UBL, et sinon celle du PDF embarqué" do
      pdf_avec_comm = text_pdf(["BRUYERRE", "Communication +++000/1223/35386+++"])
      avec, sans = relever([
                             raw_ubl_mail(message_id: "c1@okioki.be", xml: ubl_xml(payment_id: "+++000/0024/11862+++", pdf: pdf)),
                             raw_ubl_mail(message_id: "c2@okioki.be", xml: ubl_xml(number: "X-2", payment_id: nil, pdf: pdf_avec_comm))
                           ])
      [avec, sans].each { |m| MailIntake::Analyze.new(mail_message: m, jev: jev).run! }

      expect(avec.mail_attachments.find_by(content_type: "application/pdf").proposal["payment_reference"])
        .to eq("value" => "+++000/0024/11862+++", "source" => "ubl")
      expect(sans.mail_attachments.find_by(content_type: "application/pdf").proposal["payment_reference"])
        .to eq("value" => "+++000/1223/35386+++", "source" => "code")
    end

    it "écarte une communication structurée dont la clé est fausse" do
      message = relever([raw_ubl_mail(message_id: "c3@okioki.be", xml: ubl_xml(pdf: pdf))]).first

      MailIntake::Analyze.new(mail_message: message, jev: jev).run!

      expect(message.mail_attachments.find_by(content_type: "application/pdf").proposal).not_to have_key("payment_reference")
    end

    it "reconnaît nos propres factures de vente, qui ne proposent pas d'achat" do
      xml = ubl_xml(supplier: "Fondation Les 4 Sources", supplier_vat: "BE0508977707", customer_vat: "BE0881260539", pdf: pdf)
      message = relever([raw_ubl_mail(message_id: "u3@okioki.be", xml: xml, subject: "UBL Invoice - SOLIDARCITE - 2026-093 [Sales]")]).first

      MailIntake::Analyze.new(mail_message: message, jev: jev).run!

      expect(message.mail_attachments.map(&:kind)).to contain_exactly("ubl_data", "sales")
      expect(message.mail_attachments.reload.select(&:invoice_like?)).to be_empty
      expect(message.reload.triage.dig("nature", "value")).to eq("sales")
    end

    it "relit l'UBL d'un mail relevé avant que Claudy sache le garder" do
      message = relever([raw_ubl_mail(message_id: "u4@okioki.be", xml: ubl_xml(pdf: pdf))]).first
      message.mail_attachments.each { |a| a.file.purge }
      message.mail_attachments.where.not(embedded_in_id: nil).delete_all
      message.mail_attachments.delete_all
      message.update!(triage: { "nature" => { "value" => "invoice" } }, analyzed_at: 1.hour.ago)

      expect(MailMessage.to_analyze).to include(message)
      MailIntake::Analyze.new(mail_message: message, jev: jev).run!

      expect(message.mail_attachments.reload.map(&:content_type)).to contain_exactly("application/xml", "application/pdf")
    end
  end
end
