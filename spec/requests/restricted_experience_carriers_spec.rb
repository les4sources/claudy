require "rails_helper"

# Feature 2 — accès restreint « porteur d'activités » : un utilisateur avec
# `restricted_to_experiences: true` est cloisonné sur son planning d'activités
# (liste de SES activités) et toute autre page le renvoie vers ce planning.
RSpec.describe "Accès restreint aux porteurs d'activités", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:carrier_human) { Human.create!(name: "Porteur Restreint") }
  let(:other_human)   { Human.create!(name: "Autre Porteur") }

  let(:restricted_user) do
    User.create!(email: "porteur@les4sources.be", password: "password123",
                 human: carrier_human, restricted_to_experiences: true)
  end
  let(:admin_user) do
    User.create!(email: "admin@les4sources.be", password: "password123")
  end

  let!(:own_experience)   { Experience.create!(name: "Balade du porteur", human: carrier_human) }
  let!(:other_experience) { Experience.create!(name: "Atelier voisin", human: other_human) }

  context "utilisateur restreint" do
    before { sign_in restricted_user }

    it "est redirigé depuis la racine vers son planning d'activités" do
      get root_path
      expect(response).to redirect_to(experiences_path)
    end

    it "est redirigé depuis /stays vers son planning" do
      get stays_path
      expect(response).to redirect_to(experiences_path)
    end

    it "est redirigé depuis /customers vers son planning" do
      get customers_path
      expect(response).to redirect_to(experiences_path)
    end

    it "accède à son planning d'activités et n'y voit que les siennes" do
      get experiences_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Balade du porteur")
      expect(response.body).not_to include("Atelier voisin")
    end

    it "accède à la fiche de SA propre activité" do
      get experience_path(own_experience)
      expect(response).to have_http_status(:ok)
    end

    it "est renvoyé vers son planning s'il cible l'activité d'un autre porteur" do
      get experience_path(other_experience)
      expect(response).to redirect_to(experiences_path)
    end
  end

  context "utilisateur admin (non restreint) — comportement inchangé" do
    before { sign_in admin_user }

    it "accède normalement à la racine" do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "accède normalement à /stays" do
      get stays_path
      expect(response).to have_http_status(:ok)
    end

    it "voit toutes les activités sur /experiences" do
      get experiences_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Balade du porteur")
      expect(response.body).to include("Atelier voisin")
    end
  end
end
