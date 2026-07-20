require "rails_helper"

# Phase 1 de l'epic #25 — renommage UI « Expérience » → « Activité »
# (le modèle et les routes restent `Experience*` ; seuls les libellés changent)
RSpec.describe "Experiences (UI « Activités »)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  before { sign_in user }

  describe "GET /experiences" do
    # 2026-07-20 : le libellé du MENU paramètres est redevenu « Expériences »
    # (décision Michael) — l'interdiction globale du mot est levée ; les pages
    # elles-mêmes continuent de parler d'« activités ».
    it "affiche le libellé « Activités » et le lien de création" do
      get experiences_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Activités")
      expect(response.body).to include("Nouvelle activité")
    end
  end

  describe "GET /experiences/new" do
    it "intitule la page « Nouvelle activité »" do
      get new_experience_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nouvelle activité")
      # l'apostrophe est échappée en HTML (&#39;)
      expect(response.body).to include("Libellé de l&#39;activité")
      expect(response.body).to include("Porteur·euse d&#39;activité")
    end
  end
end
