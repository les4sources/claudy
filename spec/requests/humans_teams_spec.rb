require "rails_helper"

# Epic #239, phase 4 — les pôles d'une personne se lisent depuis sa fiche et
# depuis l'index de l'équipe. On ne les MODIFIE pas ici : le raccourci renvoie
# à l'écran du pôle, seul endroit où l'appartenance s'édite.
RSpec.describe "Équipe — les pôles d'une personne", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "equipe@les4sources.be", password: "password123") }
  let!(:accueil) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let!(:cuisine) { Team.create!(name: "Pôle Cuisine", kind: "analytic") }
  let!(:stephanie) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let!(:marc) { Human.create!(name: "Marc", email: "marc@les4sources.be", status: "active") }

  before { sign_in user }

  describe "la fiche humain" do
    before do
      TeamMembership.create!(team: cuisine, human: stephanie, role: "referent")
      TeamMembership.create!(team: accueil, human: stephanie, role: "member")
    end

    it "liste les pôles avec leur rôle et un lien vers la page du pôle" do
      get human_path(stephanie)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pôle Cuisine")
      expect(response.body).to include("Pôle Accueil")
      expect(response.body).to include("Référent·e")
      expect(response.body).to include("Membre")
      expect(response.body).to include(team_path(cuisine))
      expect(response.body).to include(team_path(accueil))
    end

    # Deux pôles : le raccourci ne peut pas choisir à la place de l'humain, il
    # mène à Paramètres > Pôles.
    it "renvoie à Paramètres > Pôles quand la personne a plusieurs pôles" do
      get human_path(stephanie)

      expect(response.body).to match(/Modifier ses pôles/)
      expect(response.body).to include(%(href="#{teams_path}"))
    end

    it "mène directement à l'édition du pôle quand il n'y en a qu'un" do
      get human_path(marc)
      expect(response.body).not_to include(edit_team_path(accueil))

      TeamMembership.create!(team: accueil, human: marc, role: "member")
      get human_path(marc)

      expect(response.body).to include(%(href="#{edit_team_path(accueil)}"))
    end

    it "le dit franchement quand la personne n'appartient à aucun pôle" do
      get human_path(marc)

      expect(response.body).to include("n&#39;appartient à aucun pôle").or include("n'appartient à aucun pôle")
    end

    # L'appartenance s'édite dans l'écran du pôle : pas de formulaire ici.
    it "n'ouvre aucun formulaire d'appartenance sur la fiche" do
      get human_path(stephanie)

      expect(response.body).not_to include(team_memberships_path(cuisine))
    end
  end

  describe "l'index de l'équipe" do
    before { TeamMembership.create!(team: cuisine, human: stephanie, role: "referent") }

    it "affiche les pôles de chacun en badges" do
      get humans_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pôles")
      expect(response.body).to include("Pôle Cuisine")
      expect(response.body).to include(team_path(cuisine))
    end

    it "ne fabrique pas de badge pour qui n'a pas de pôle" do
      get humans_path

      # Marc n'a aucun pôle : sa cellule porte le tiret, pas un badge.
      expect(response.body).to include("Marc")
      expect(response.body).to include(%(<span class="text-gray-300">—</span>))
    end
  end
end
