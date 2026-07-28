require "rails_helper"

# Journalisation des emails à l'envoi. L'observer ActionMailer est enregistré
# dans config/application.rb : un `deliver_now` doit suffire à créer la ligne.
RSpec.describe SentEmails::Recorder do
  let!(:customer) do
    Customer.create!(email: "cliente@example.com", customer_type: "individual",
                     first_name: "Ada", last_name: "Lovelace")
  end

  describe "à la livraison d'un email" do
    it "journalise l'email envoyé au client, avec sujet, corps et mailer" do
      expect {
        PortalMailer.login_code(email: customer.email, code: "123456", expires_at: 10.minutes.from_now).deliver_now
      }.to change(SentEmail, :count).by(1)

      sent = SentEmail.last
      expect(sent.customer).to eq(customer)
      expect(sent.to_email).to eq(customer.email)
      expect(sent.subject).to eq("Votre code de connexion — Les 4 Sources")
      expect(sent.body_html).to include("123456")
      expect(sent.body_text).to include("123456")
      expect(sent.mailer).to eq("PortalMailer")
      expect(sent.source).to eq("app")
      expect(sent.sent_at).to be_within(5.seconds).of(Time.current)
    end

    it "ignore un destinataire qui n'est pas un client (équipe, porteur d'activité)" do
      expect {
        PortalMailer.login_code(email: "equipe@les4sources.be", code: "123456", expires_at: 10.minutes.from_now).deliver_now
      }.not_to change(SentEmail, :count)
    end

    it "retrouve le client quelle que soit la casse de l'adresse" do
      expect {
        PortalMailer.login_code(email: "CLIENTE@Example.com", code: "123456", expires_at: 10.minutes.from_now).deliver_now
      }.to change(SentEmail, :count).by(1)

      expect(SentEmail.last.customer).to eq(customer)
    end
  end

  describe "périmètre des destinataires" do
    # Le bcc d'archivage (ApplicationMailer.default bcc:) et les copies internes
    # ne sont PAS l'historique du client : seul le champ `to` compte.
    it "ne journalise ni le bcc ni le cc" do
      message = Mail.new do
        to      "personne@example.com"
        cc      "cliente@example.com"
        bcc     "cliente@example.com"
        subject "Copie interne"
        body    "Rien à voir"
      end

      expect { described_class.record(message) }.not_to change(SentEmail, :count)
    end

    it "journalise chaque destinataire `to` qui est un client" do
      other = Customer.create!(email: "second@example.com", customer_type: "individual", first_name: "Bob", last_name: "Martin")

      message = Mail.new do
        to      ["cliente@example.com", "second@example.com", "inconnu@example.com"]
        subject "Envoi groupé"
        body    "Bonjour"
      end

      expect { described_class.record(message) }.to change(SentEmail, :count).by(2)
      expect(SentEmail.pluck(:customer_id)).to match_array([customer.id, other.id])
    end
  end

  describe "dédoublonnage avec le backfill Postmark" do
    it "ne recrée pas une ligne pour un MessageID déjà journalisé" do
      SentEmail.create!(customer: customer, to_email: customer.email, subject: "Déjà là",
                        sent_at: 1.day.ago, postmark_message_id: "pm-42", source: "postmark")

      message = Mail.new do
        to      "cliente@example.com"
        subject "Doublon"
        body    "Bonjour"
      end
      message["X-PM-Message-Id"] = "pm-42"

      expect { described_class.record(message) }.not_to change(SentEmail, :count)
    end

    it "conserve le MessageID Postmark quand il est présent" do
      message = Mail.new do
        to      "cliente@example.com"
        subject "Envoi réel"
        body    "Bonjour"
      end
      message["X-PM-Message-Id"] = "pm-99"

      described_class.record(message)
      expect(SentEmail.last.postmark_message_id).to eq("pm-99")
    end
  end

  describe "robustesse" do
    # Journaliser ne doit jamais faire échouer un envoi.
    it "avale l'erreur et laisse l'email partir" do
      allow(described_class).to receive(:record).and_raise(StandardError, "boom")

      expect {
        PortalMailer.login_code(email: customer.email, code: "123456", expires_at: 10.minutes.from_now).deliver_now
      }.not_to raise_error

      # …et l'observer a bien été sollicité (sinon le test ne prouverait rien).
      expect(described_class).to have_received(:record)
    end
  end
end
