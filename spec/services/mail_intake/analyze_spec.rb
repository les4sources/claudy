require "rails_helper"
require Rails.root.join("spec/support/mail_intake_helpers")

RSpec.describe MailIntake::Analyze do
  let!(:fondation) { LegalEntity.create!(name: "Fondation Les 4 Sources", form: "foundation", vat_number: "BE0508977707") }
  let!(:srl) { LegalEntity.create!(name: "Domaine d'Ahinvaux SRL", form: "srl", vat_number: "BE0867485747") }
  let!(:proximus) { ThirdParty.create!(name: "Proximus", kind: "supplier", vat_number: "BE0202239951") }
  let!(:luminus) { ThirdParty.create!(name: "Luminus", kind: "supplier") }
  let(:account) { MailAccount.create!(address: "compta@les4sources.be", purpose: "accounting") }
  let(:lines) do
    ["Proximus SA - TVA BE 0202.239.951", "Client : Fondation Les 4 Sources BE0508977707",
     "Facture n° 2026-77812 du 12/09/2026", "Sous-total 69,52", "Total a payer 84,12 EUR",
     "Echeance 15/10/2026", "IBAN BE68 5390 0754 7034"]
  end
  let(:message) do
    imap = MailIntakeHelpers::FakeImap.new({ 1 => raw_mail(message_id: "x@proximus.be", pdf: text_pdf(lines)) })
    MailIntake::Sync.new(mail_account: account, imap: imap).run!.first
  end
  let(:jev) do
    MailIntakeHelpers::FakeJev.new do |id, _question|
      { "kind" => { "choice" => "invoice", "confidence" => 0.97 },
        "total" => { "choice" => "84,12", "confidence" => 0.93 },
        "issued_on" => { "choice" => "12/09/2026", "confidence" => 0.9 },
        "due_on" => { "choice" => "15/10/2026", "confidence" => 0.62 },
        "number" => { "choice" => "2026-77812", "confidence" => 0.95 },
        "nature" => { "choice" => "invoice", "confidence" => 0.99 } }[id]
    end
  end

  it "reconnaît fournisseur et entité par leur TVA, sans les demander à Jev" do
    described_class.new(mail_message: message, jev: jev).run!

    proposal = message.mail_attachments.first.reload.proposal
    expect(proposal["third_party_id"]).to eq("value" => proximus.id, "source" => "code")
    expect(proposal["legal_entity_id"]).to eq("value" => fondation.id, "source" => "code")
    asked = jev.calls.flat_map { |c| c[:questions].keys }
    expect(asked).not_to include("supplier", "legal_entity")
  end

  it "propose total, dates et numéro tels que choisis parmi les candidats, avec la confiance de Jev" do
    described_class.new(mail_message: message, jev: jev).run!

    attachment = message.mail_attachments.first.reload
    expect(attachment.proposed(:total_cents)).to eq(8_412)
    expect(attachment.proposed(:issued_on)).to eq("2026-09-12")
    expect(attachment.proposed(:due_on)).to eq("2026-10-15")
    expect(attachment.proposed(:number)).to eq("2026-77812")
    expect(attachment.proposal.dig("due_on", "confidence")).to eq(0.62)
    expect(attachment.kind).to eq("invoice")
    expect(message.reload.triage.dig("nature", "value")).to eq("invoice")
    expect(message.analyzed_at).to be_present
  end

  it "chaque option donnée à Jev est un texte présent dans le PDF" do
    described_class.new(mail_message: message, jev: jev).run!

    text = message.mail_attachments.first.reload.text_content
    total_options = jev.calls.find { |c| c[:questions].key?("total") }[:questions]["total"][:criteria].keys - ["aucun"]
    expect(total_options).to all(satisfy { |raw| text.include?(raw) })
  end

  it "écarte une réponse qui n'est pas un des candidats" do
    menteur = MailIntakeHelpers::FakeJev.new { |id, _| { "choice" => "999,99", "confidence" => 1.0 } if id == "total" }

    described_class.new(mail_message: message, jev: menteur).run!

    expect(message.mail_attachments.first.reload.proposed(:total_cents)).to be_nil
  end

  it "demande le fournisseur à Jev quand le code ne le trouve pas" do
    proximus.update!(vat_number: nil)
    jev_tiers = MailIntakeHelpers::FakeJev.new { |id, _| { "choice" => "Proximus", "confidence" => 0.88 } if id == "supplier" }

    described_class.new(mail_message: message, jev: jev_tiers).run!

    expect(message.mail_attachments.first.reload.proposal["third_party_id"])
      .to include("value" => proximus.id, "source" => "jev", "confidence" => 0.88)
  end

  it "sans Jev, le mail est analysé quand même : pas de proposition, pas d'erreur levée" do
    described_class.new(mail_message: message, jev: MailIntakeHelpers::FakeJev.new(configured: false)).run!

    attachment = message.mail_attachments.first.reload
    expect(attachment.proposal["error"]).to eq("Jev n'est pas configuré")
    expect(attachment.proposal["third_party_id"]).to include("source" => "code")
    expect(message.reload.analyzed_at).to be_present
  end

it "fournisseur inconnu : prépare sa création — TVA et IBAN par le code, nom choisi par Jev hors de nos propres noms" do
  proximus.update!(vat_number: nil)
  nommeur = MailIntakeHelpers::FakeJev.new { |id, _| { "choice" => "Proximus", "confidence" => 0.91 } if id == "supplier_name" }

  described_class.new(mail_message: message, jev: nommeur).run!

  attachment = message.mail_attachments.first.reload
  expect(attachment.supplier_draft).to eq(name: "Proximus", vat_number: "BE0202239951", iban: "BE68539007547034")
  options = nommeur.calls.find { |c| c[:questions].key?("supplier_name") }[:questions]["supplier_name"][:criteria].keys
  expect(options).to include("Proximus", "Proximus SA - TVA BE 0202.239.951")
  expect(options.grep(/Fondation Les 4 Sources/)).to be_empty
end

it "fournisseur reconnu : ne demande pas son nom" do
  described_class.new(mail_message: message, jev: jev).run!

  expect(jev.calls.flat_map { |c| c[:questions].keys }).not_to include("supplier_name")
end

it "relit les mails encore à traiter quand l'analyse a progressé, jamais ceux déjà classés" do
  described_class.new(mail_message: message, jev: jev).run!
  expect(MailMessage.to_analyze).to be_empty

  message.update!(triage: message.triage.except("version"))
  expect(MailMessage.to_analyze).to contain_exactly(message)

  message.update!(status: "filed")
  expect(MailMessage.to_analyze).to be_empty
end

  it "ne crée jamais de facture" do
    expect { described_class.new(mail_message: message, jev: jev).run! }.not_to change(PurchaseInvoice, :count)
  end
end
