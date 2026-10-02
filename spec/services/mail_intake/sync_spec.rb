require "rails_helper"
require Rails.root.join("spec/support/mail_intake_helpers")

RSpec.describe MailIntake::Sync do
  let(:account) { MailAccount.create!(address: "compta@les4sources.be", purpose: "accounting") }
  let(:pdf) { text_pdf(["Facture F-1", "Total 84,12 EUR"]) }
  let(:imap) do
    MailIntakeHelpers::FakeImap.new({ 7 => raw_mail(message_id: "a@proximus.be", pdf: pdf),
                                      9 => raw_mail(message_id: "b@luminus.be", subject: "Sans pièce") })
  end

  it "crée un mail par message nouveau, avec sa pièce PDF et son brut" do
    created = described_class.new(mail_account: account, imap: imap).run!

    expect(created.size).to eq(2)
    message = account.mail_messages.find_by!(message_id: "a@proximus.be")
    expect(message).to have_attributes(from_address: "factures@proximus.be", from_name: "Proximus",
                                       subject: "Votre facture", imap_uid: 7, status: "pending")
    expect(message.body_text).to include("veuillez trouver votre facture")
    expect(message.raw).to be_attached
    expect(message.mail_attachments.map(&:filename)).to eq(["facture.pdf"])
    expect(message.mail_attachments.first.sha256).to eq(Digest::SHA256.hexdigest(pdf))
    expect(account.reload).to have_attributes(last_uid: 9, uid_validity: 42, last_error: nil)
  end

  it "ne change rien sur le serveur : EXAMINE, BODY.PEEK[], aucune autre commande" do
    described_class.new(mail_account: account, imap: imap).run!

    verbs = imap.commands.map(&:first).uniq
    expect(verbs).to contain_exactly(:examine, :status, :uid_search, :uid_fetch)
    fetches = imap.commands.select { |c| c.first == :uid_fetch }
    expect(fetches).to all(satisfy { |c| c.last.include?("BODY.PEEK[]") && c.last.none? { |a| a == "BODY[]" } })
  end

  it "ne remonte que 90 jours au premier passage, puis suit le dernier UID" do
    described_class.new(mail_account: account, imap: imap).run!
    expect(imap.commands.find { |c| c.first == :uid_search }.last.first).to eq("SINCE")

    described_class.new(mail_account: account.reload, imap: imap).run!
    expect(imap.commands.select { |c| c.first == :uid_search }.last.last).to eq(["UID", "10:*"])
  end

  it "rejouée, ne crée aucun doublon — même quand le serveur renvoie le dernier message pour `UID n:*`" do
    described_class.new(mail_account: account, imap: imap).run!

    expect { described_class.new(mail_account: account.reload, imap: imap).run! }.not_to change(MailMessage, :count)
  end

  it "repart de zéro si UIDVALIDITY change, sans doubler les mails déjà connus" do
    described_class.new(mail_account: account, imap: imap).run!
    imap.uid_validity = 99

    expect { described_class.new(mail_account: account.reload, imap: imap).run! }.not_to change(MailMessage, :count)
    expect(account.reload.uid_validity).to eq(99)
  end

  it "sans mot de passe dans l'ENV, s'arrête avec un message clair et le garde sur la boîte" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("MAIL_PASSWORD_COMPTA").and_return(nil)

    expect { described_class.new(mail_account: account).run! }
      .to raise_error(MailIntake::Sync::MissingPassword, /MAIL_PASSWORD_COMPTA/)
    expect(account.reload.last_error).to include("MAIL_PASSWORD_COMPTA")
  end

  it "ignore les petites images inline (logos) mais garde une photo jointe" do
    logo = Mail.new do
      from "a@b.be"
      message_id "<logo@b.be>"
    end
    logo.text_part = Mail::Part.new { body "Voir photo" }
    logo.add_file(filename: "logo.png", content: "x" * 500)
    logo.add_file(filename: "ticket.jpg", content: "y" * 30_000)
    imap = MailIntakeHelpers::FakeImap.new({ 1 => logo.to_s })

    described_class.new(mail_account: account, imap: imap).run!

    expect(MailAttachment.pluck(:filename)).to eq(["ticket.jpg"])
  end
end
