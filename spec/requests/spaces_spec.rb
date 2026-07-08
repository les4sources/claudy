require "rails_helper"

# Issue #37 — CRUD admin des espaces dans les paramètres.
RSpec.describe "Spaces (CRUD admin)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  before { sign_in user }

  describe "GET /spaces" do
    it "liste les espaces triés par position avec le menu paramètres" do
      Space.create!(name: "Grande Salle", capacity: 1, position: 2)
      Space.create!(name: "Bois", capacity: 5, position: 1)

      get spaces_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Espaces")
      expect(response.body).to include("Grande Salle")
      expect(response.body).to include("Bois")
      # tri par position : Bois (1) avant Grande Salle (2)
      expect(response.body.index("Bois")).to be < response.body.index("Grande Salle")
      # badge multi-groupe pour l'espace partagé
      expect(response.body).to include("multi-groupe")
      # menu secondaire paramètres présent (lien Produits voisin)
      expect(response.body).to include("Produits")
    end
  end

  describe "GET /spaces/new" do
    it "affiche le formulaire de création" do
      get new_space_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nouvel espace")
      expect(response.body).to include("Capacité")
    end
  end

  describe "POST /spaces" do
    it "crée un espace et redirige vers sa page" do
      expect {
        post spaces_path, params: {
          space: { name: "Pâture est", description: "Tente", code: "PAT-E", capacity: 5, position: 3 }
        }
      }.to change(Space, :count).by(1)

      space = Space.order(:created_at).last
      expect(space.name).to eq("Pâture est")
      expect(space.capacity).to eq(5)
      expect(response).to redirect_to(space_path(space))
    end

    it "refuse une capacité invalide et réaffiche le formulaire" do
      expect {
        post spaces_path, params: { space: { name: "Cassé", capacity: 0 } }
      }.not_to change(Space, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /spaces/:id" do
    it "met à jour la capacité" do
      space = Space.create!(name: "Bois", capacity: 3)
      patch space_path(space), params: { space: { name: "Bois", capacity: 8 } }
      expect(response).to redirect_to(space_path(space))
      expect(space.reload.capacity).to eq(8)
    end
  end

  describe "DELETE /spaces/:id" do
    it "supprime en soft-delete (retiré de l'index, retrouvable via unscoped)" do
      space = Space.create!(name: "À supprimer", capacity: 1)

      delete space_path(space)

      expect(response).to redirect_to(spaces_path)
      expect(Space.where(id: space.id)).to be_empty
      deleted = Space.unscoped.find(space.id)
      expect(deleted.deleted_at).to be_present
    end
  end
end
