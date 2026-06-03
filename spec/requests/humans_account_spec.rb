require "rails_helper"

# Epic #25 — Phase 2 (comptes porteurs) : carte « Compte d'accès » sur la fiche
# d'un membre et action de création de compte.
RSpec.describe "Humans — comptes d'accès porteurs", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  before { sign_in user }

  describe "GET /humans/:id" do
    it "propose de créer un compte quand le membre a un email mais pas de compte" do
      human = Human.create!(name: "Porteur Sans Compte", email: "porteur@example.com")
      get human_path(human)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Créer un compte")
    end

    it "indique « Compte actif » quand le membre a déjà un compte" do
      human = Human.create!(name: "Porteur Avec Compte", email: "avec@example.com")
      User.create!(email: "avec@example.com", password: "password123", human: human)
      get human_path(human)
      expect(response.body).to include("Compte actif")
      expect(response.body).not_to include("Créer un compte")
    end

    it "invite à ajouter un email quand le membre n'en a pas" do
      human = Human.create!(name: "Porteur Sans Email")
      get human_path(human)
      expect(response.body).to include("pour pouvoir lui créer un compte")
    end
  end

  describe "POST /humans/:id/create_account" do
    it "crée le compte et redirige vers la fiche" do
      human = Human.create!(name: "Nouveau Porteur", email: "nouveau@example.com")

      expect {
        post create_account_human_path(human)
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(human_path(human))
      expect(human.reload.user).to be_present
      expect(human.user.email).to eq("nouveau@example.com")
    end

    it "refuse sans email et ne crée aucun compte" do
      human = Human.create!(name: "Porteur Sans Email")

      expect {
        post create_account_human_path(human)
      }.not_to change(User, :count)

      expect(response).to redirect_to(human_path(human))
    end
  end
end
