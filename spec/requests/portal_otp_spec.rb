require "rails_helper"

# Epic #126, Phase 2 — portail client, connexion par code à usage unique.
RSpec.describe "Portail client — connexion OTP", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers
  let!(:customer) do
    Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com")
  end

  def last_code
    ActionMailer::Base.deliveries.last.body.encoded[/\b\d{6}\b/]
  end

  before { ActionMailer::Base.deliveries.clear }

  describe "GET /portail" do
    it "affiche le formulaire d'email" do
      get portal_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mon espace client")
    end
  end

  describe "POST /portail/code" do
    it "envoie un code à un client connu" do
      expect {
        post portal_code_path, params: { email: "ana@example.com" }
      }.to change { PortalOtp.count }.by(1)

      expect(response).to redirect_to(portal_verify_path)
      follow_redirect!
      expect(response.body).to include("Si un compte existe")
    end

    it "throttle l'émission : pas plus de 5 codes par heure et par email" do
      5.times { post portal_code_path, params: { email: "ana@example.com" } }

      expect {
        post portal_code_path, params: { email: "ana@example.com" }
      }.not_to change { PortalOtp.count }

      # La réponse reste neutre : rien ne dit que l'envoi a été bloqué.
      expect(response).to redirect_to(portal_verify_path)

      travel_to(61.minutes.from_now) do
        expect {
          post portal_code_path, params: { email: "ana@example.com" }
        }.to change { PortalOtp.count }.by(1)
      end
    end

    it "répond EXACTEMENT pareil à un email inconnu, sans créer de code" do
      post portal_code_path, params: { email: "ana@example.com" }
      expect(response).to redirect_to(portal_verify_path)
      follow_redirect!
      known_body = response.body

      PortalOtp.delete_all

      expect {
        post portal_code_path, params: { email: "inconnu@example.com" }
      }.not_to change { PortalOtp.count }
      expect(response).to redirect_to(portal_verify_path)
      follow_redirect!

      # Les deux réponses sont identiques au caractère près, une fois l'email
      # saisi (simplement réaffiché dans le formulaire) neutralisé : rien dans
      # le statut ni le corps ne dit si un compte existe.
      normalize = ->(body, email) { body.gsub(CGI.escape(email), "EMAIL").gsub(email, "EMAIL") }

      expect(normalize.call(response.body, "inconnu@example.com"))
        .to eq(normalize.call(known_body, "ana@example.com"))
      expect(response).to have_http_status(:ok)
    end

    it "ne sert JAMAIS un email fourre-tout" do
      Customer::CATCH_ALL_EMAILS.each do |catch_all|
        Customer.find_or_create_by!(email: catch_all) { |c| c.first_name = "Fourre-tout" }

        expect {
          post portal_code_path, params: { email: catch_all }
        }.not_to change { PortalOtp.count }

        expect(response).to redirect_to(portal_verify_path)
        follow_redirect!
        expect(response.body).to include("Si un compte existe")
      end
    end
  end

  describe "POST /portail/connexion" do
    before do
      perform_enqueued_jobs do
        post portal_code_path, params: { email: "ana@example.com" }
      end
    end

    it "connecte le client avec le bon code" do
      post portal_login_path, params: { email: "ana@example.com", code: last_code }

      expect(response).to redirect_to(portal_stays_path)
      follow_redirect!
      expect(response.body).to include("Mes séjours")
    end

    it "refuse un code faux et brûle le code après 5 tentatives" do
      5.times do
        post portal_login_path, params: { email: "ana@example.com", code: "000000" }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      # Même le VRAI code ne passe plus : il a été brûlé.
      post portal_login_path, params: { email: "ana@example.com", code: last_code }
      expect(response).to have_http_status(:unprocessable_entity)

      get portal_stays_path
      expect(response).to redirect_to(portal_path)
    end

    it "refuse un code expiré" do
      code = last_code
      PortalOtp.last.update!(expires_at: 1.minute.ago)

      post portal_login_path, params: { email: "ana@example.com", code: code }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "ne stocke jamais le code en clair" do
      expect(PortalOtp.last.code_digest).not_to eq(last_code)
      expect(PortalOtp.column_names).not_to include("code")
    end
  end

  describe "session" do
    def sign_in_portal_as(email)
      perform_enqueued_jobs { post portal_code_path, params: { email: email } }
      post portal_login_path, params: { email: email, code: last_code }
    end

    it "pose un cookie httponly de 24 h" do
      sign_in_portal_as("ana@example.com")

      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
      portal_cookie = set_cookie.lines.find { |line| line.include?("portal_customer_id") }

      expect(portal_cookie).to be_present
      expect(portal_cookie.downcase).to include("httponly")
      expires = portal_cookie[/expires=([^;]+)/i, 1]
      expect(Time.parse(expires)).to be_within(5.minutes).of(24.hours.from_now)
    end

    it "se termine à la déconnexion" do
      sign_in_portal_as("ana@example.com")

      delete portal_logout_path
      expect(response).to redirect_to(portal_path)

      get portal_stays_path
      expect(response).to redirect_to(portal_path)
    end

    it "n'ouvre AUCUN accès admin" do
      sign_in_portal_as("ana@example.com")

      get stays_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "n'est pas ouverte par une session admin Devise" do
      # Une admin connectée ne devient pas cliente du portail pour autant.
      sign_in User.create!(email: "agent@les4sources.be", password: "password123")

      get portal_stays_path
      expect(response).to redirect_to(portal_path)
    end
  end
end
