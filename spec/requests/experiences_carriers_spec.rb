require "rails_helper"

# Epic #25 — Phase 2 (comptes porteurs) : le formulaire d'activité ne propose
# comme porteur·euse que des personnes pouvant avoir un compte (= ayant un email).
RSpec.describe "Experiences — sélection du porteur", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  before { sign_in user }

  describe "GET /experiences/new" do
    it "ne propose comme porteur que les personnes ayant un email" do
      with_email    = Human.create!(name: "Avec Email Porteur", email: "porteur@example.com")
      without_email = Human.create!(name: "Aucun Email Ici")

      get new_experience_path

      expect(response).to have_http_status(:ok)
      # On cible les radios du champ porteur : le layout (avatars/tooltips) peut
      # légitimement afficher tous les humans ailleurs sur la page.
      carrier_radio = ->(human) { /name="experience\[human_id\]"[^>]*value="#{human.id}"|value="#{human.id}"[^>]*name="experience\[human_id\]"/ }
      expect(response.body).to match(carrier_radio.call(with_email))
      expect(response.body).not_to match(carrier_radio.call(without_email))
      expect(response.body).to include("compte à créer")
    end

    it "affiche « compte actif » pour un porteur disposant déjà d'un compte" do
      human = Human.create!(name: "Porteur Connecté", email: "connecte@example.com")
      User.create!(email: "connecte@example.com", password: "password123", human: human)

      get new_experience_path

      expect(response.body).to include("Porteur Connecté")
      expect(response.body).to include("compte actif")
    end
  end
end
