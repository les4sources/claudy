require "rails_helper"

# Epic #359, phase 1 — la porte de l'espace artisan, et ses cloisons.
RSpec.describe "Portail — espace artisan", type: :request do
  include ActiveJob::TestHelper

  let!(:eline) do
    Consignor.create!(name: "Eline", settlement_mode: "invoice",
                      email: "eline@example.com", portal_enabled: true)
  end
  let!(:bruno) do
    Consignor.create!(name: "Bruno", settlement_mode: "invoice",
                      email: "bruno@example.com", portal_enabled: true)
  end
  let!(:client) { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com") }

  before { ActionMailer::Base.deliveries.clear }

  def request_code(email, context:)
    perform_enqueued_jobs { post portal_code_path, params: { email: email, context: context } }
    ActionMailer::Base.deliveries.last&.body&.encoded&.[](/\b\d{6}\b/)
  end

  def sign_in_consignor(email)
    code = request_code(email, context: "consignor")
    post portal_login_path, params: { email: email, code: code }
  end

  def sign_in_customer(email)
    code = request_code(email, context: "stays")
    post portal_login_path, params: { email: email, code: code }
  end

  describe "la page d'entrée" do
    it "propose la troisième porte" do
      get portal_path

      expect(response.body).to include("Je suis artisan en dépôt-vente")
    end

    it "adresse l'artisan quand le contexte est le sien" do
      get portal_path(context: "consignor")

      expect(response.body).to include("Votre espace artisan")
      expect(response.body).to include("plutôt un séjour")
    end
  end

  describe "l'émission du code" do
    it "envoie un code à un artisan dont l'espace est ouvert" do
      expect {
        post portal_code_path, params: { email: "eline@example.com", context: "consignor" }
      }.to change { PortalOtp.count }.by(1)
    end

    it "n'en envoie pas à un artisan dont l'espace est fermé" do
      eline.update!(portal_enabled: false)

      expect {
        post portal_code_path, params: { email: "eline@example.com", context: "consignor" }
      }.not_to change { PortalOtp.count }
    end

    # Anti-énumération : un client des 4 Sources n'est pas un artisan, et la
    # réponse ne dit jamais laquelle des deux choses cloche.
    it "n'en envoie pas à un simple client, et répond pareil" do
      expect {
        post portal_code_path, params: { email: "ana@example.com", context: "consignor" }
      }.not_to change { PortalOtp.count }

      expect(response).to redirect_to(portal_verify_path)
    end
  end

  describe "la connexion" do
    it "ouvre l'espace de l'artisan" do
      sign_in_consignor("eline@example.com")

      expect(response).to redirect_to(portal_consignments_path)
      follow_redirect!
      expect(response.body).to include("Mon dépôt-vente", "Eline")
    end

    it "refuse un code valide dont l'espace a été fermé entre-temps" do
      code = request_code("eline@example.com", context: "consignor")
      eline.update!(portal_enabled: false)

      post portal_login_path, params: { email: "eline@example.com", code: code }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("incorrect ou expiré")
    end
  end

  describe "le cloisonnement" do
    it "exige une session artisan" do
      get portal_consignments_path

      expect(response).to redirect_to(portal_path(context: "consignor"))
    end

    it "ferme les séjours et le coworking à un artisan connecté" do
      sign_in_consignor("eline@example.com")

      get portal_stays_path
      expect(response).to redirect_to(portal_path)

      get portal_coworking_path
      expect(response).to redirect_to(portal_path(context: "coworking"))
    end

    it "ferme l'espace artisan à un client connecté" do
      sign_in_customer("ana@example.com")

      get portal_consignments_path

      expect(response).to redirect_to(portal_path(context: "consignor"))
    end

    # Une seule identité à la fois : se connecter comme client ferme la session
    # artisan, sinon un même navigateur porterait les deux.
    it "ferme la session artisan quand on se connecte comme client" do
      sign_in_consignor("eline@example.com")
      sign_in_customer("ana@example.com")

      get portal_consignments_path
      expect(response).to redirect_to(portal_path(context: "consignor"))
    end

    it "ne montre jamais l'espace d'un autre artisan" do
      sign_in_consignor("eline@example.com")

      get portal_consignments_path

      expect(response.body).to include("Eline")
      expect(response.body).not_to include("Bruno")
    end

    it "coupe l'accès dès la déconnexion" do
      sign_in_consignor("eline@example.com")
      delete portal_logout_path

      get portal_consignments_path
      expect(response).to redirect_to(portal_path(context: "consignor"))
    end
  end
end
