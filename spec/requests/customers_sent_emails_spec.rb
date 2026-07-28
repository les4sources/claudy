require "rails_helper"

# Fiche client → carte « Emails envoyés » : date/heure + sujet, le sujet ouvrant
# le contenu du message dans la modale Turbo.
RSpec.describe "Customers#show — historique des emails envoyés", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)    { User.create!(email: "emails-fiche@les4sources.be", password: "password123") }
  let(:customer) do
    Customer.create!(email: "historique@example.com", customer_type: "individual",
                     first_name: "Ada", last_name: "Lovelace")
  end

  let!(:sent_email) do
    SentEmail.create!(customer: customer, to_email: customer.email,
                      subject: "Votre réservation aux 4 Sources est confirmée 👍",
                      body_html: "<p>Bonjour Ada, tout est confirmé.</p>",
                      body_text: "Bonjour Ada, tout est confirmé.",
                      mailer: "BookingMailer", tag: "booking_confirmed",
                      sent_at: Time.zone.local(2026, 7, 20, 9, 30))
  end

  before { sign_in admin }

  describe "la liste sur la fiche" do
    it "affiche le sujet et la date/heure de chaque email, du plus récent au plus ancien" do
      SentEmail.create!(customer: customer, to_email: customer.email, subject: "Plus ancien",
                        sent_at: Time.zone.local(2026, 7, 1, 8, 0))

      get customer_path(customer)

      expect(response.body).to include("Emails envoyés")
      expect(response.body).to include("Votre réservation aux 4 Sources est confirmée")
      expect(response.body).to include("20 juil. 09h30")
      expect(response.body).to include("Plus ancien")
      expect(response.body.index("Votre réservation")).to be < response.body.index("Plus ancien")
    end

    it "pointe le sujet vers la modale de consultation" do
      get customer_path(customer)

      expect(response.body).to include(customer_sent_email_path(customer, sent_email))
      expect(response.body).to include('data-turbo-frame="modal"')
    end

    it "annonce l'absence d'historique quand aucun email n'a été envoyé" do
      other = Customer.create!(email: "sans-email@example.com", customer_type: "individual",
                               first_name: "Bob", last_name: "Martin")

      get customer_path(other)

      expect(response.body).to include("Aucun email envoyé à ce client.")
    end
  end

  describe "la modale de consultation" do
    it "montre le contenu HTML de l'email, isolé dans une iframe" do
      get customer_sent_email_path(customer, sent_email)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bonjour Ada, tout est confirmé.")
      expect(response.body).to include("<iframe")
      expect(response.body).to include("sandbox")
    end

    it "affiche le destinataire et la date d'envoi" do
      get customer_sent_email_path(customer, sent_email)

      expect(response.body).to include("historique@example.com")
      expect(response.body).to include("20 juillet 2026")
    end

    it "retombe sur le texte brut quand l'email n'a pas de version HTML" do
      text_only = SentEmail.create!(customer: customer, to_email: customer.email, subject: "Texte seul",
                                    body_text: "Message en texte brut.", sent_at: Time.current)

      get customer_sent_email_path(customer, text_only)

      expect(response.body).to include("Message en texte brut.")
      expect(response.body).not_to include("<iframe")
    end

    it "signale un contenu non conservé (rétention Postmark expirée)" do
      empty = SentEmail.create!(customer: customer, to_email: customer.email, subject: "Vieux message",
                                sent_at: 6.months.ago, source: "postmark")

      get customer_sent_email_path(customer, empty)

      expect(response.body).to include("n'a pas été conservé")
    end

    # Le journal est cloisonné par client : impossible de lire l'email d'un
    # autre client en changeant l'identifiant dans l'URL.
    it "refuse un email qui n'appartient pas au client de l'URL" do
      other = Customer.create!(email: "autre@example.com", customer_type: "individual",
                               first_name: "Bob", last_name: "Martin")

      expect {
        get customer_sent_email_path(other, sent_email)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "exige une session authentifiée" do
    sign_out admin
    get customer_sent_email_path(customer, sent_email)

    expect(response).to redirect_to(new_user_session_path)
  end
end
