require "rails_helper"

# Epic #239, phase 2 — un rassemblement concerne des pôles.
RSpec.describe "Rassemblements ↔ pôles", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "poles@les4sources.be", password: "password123") }
  let!(:categorie) { GatheringCategory.create!(name: "Collectif", color: "emerald") }
  let!(:accueil) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let!(:technique) { Team.create!(name: "Pôle Technique", kind: "support") }

  before { sign_in user }

  def gathering_params(team_ids:, **overrides)
    { gathering: { gathering_category_id: categorie.id, name: "Réunion",
                   starts_at_date: "2026-10-05", starts_at_time: "14:00",
                   ends_at_date: "2026-10-05", ends_at_time: "16:00",
                   team_ids: team_ids }.merge(overrides) }
  end

  def build_gathering(teams: [], name: "Réunion")
    gathering = Gathering.create!(gathering_category: categorie, name: name,
                                  starts_at: Time.zone.parse("2026-10-05 14:00"),
                                  ends_at: Time.zone.parse("2026-10-05 16:00"))
    teams.each { |team| gathering.teams << team }
    gathering
  end

  describe "la création" do
    it "rattache le rassemblement aux pôles cochés" do
      post gatherings_path, params: gathering_params(team_ids: ["", accueil.id.to_s, technique.id.to_s])

      expect(Gathering.last.teams).to match_array([accueil, technique])
    end

    it "laisse un rassemblement transversal quand aucun pôle n'est coché" do
      post gatherings_path, params: gathering_params(team_ids: [""])

      expect(Gathering.last.teams).to be_empty
      expect(Gathering.last).to be_transversal
    end
  end

  describe "la mise à jour" do
    it "ajoute et retire par DIFF, sans toucher aux rattachements conservés" do
      gathering = build_gathering(teams: [accueil])
      conserve = gathering.gathering_teams.sole

      patch gathering_path(gathering),
            params: gathering_params(team_ids: ["", accueil.id.to_s, technique.id.to_s])

      expect(gathering.reload.teams).to match_array([accueil, technique])
      # La ligne conservée est la MÊME : pas de supprimer-recréer.
      expect(gathering.gathering_teams.find_by(team_id: accueil.id).id).to eq(conserve.id)
    end

    it "détache tous les pôles quand on décoche tout" do
      gathering = build_gathering(teams: [accueil, technique])

      patch gathering_path(gathering), params: gathering_params(team_ids: [""])

      expect(gathering.reload.teams).to be_empty
    end

    # Le formulaire de compte-rendu ne porte pas la clé : son silence ne doit
    # pas passer pour un détachement.
    it "ne détache rien quand la clé team_ids est absente" do
      gathering = build_gathering(teams: [accueil])

      patch update_report_gathering_path(gathering), params: { gathering: { report: "Compte-rendu" } }

      expect(gathering.reload.teams).to eq([accueil])
    end
  end

  describe "le formulaire" do
    it "propose les pôles en cases à cocher, cochées pour les pôles déjà liés" do
      gathering = build_gathering(teams: [accueil])

      get edit_gathering_path(gathering)

      expect(response.body).to include("Pôles concernés", "Pôle Accueil", "Pôle Technique")
      expect(response.body).to include("Aucun pôle coché = rassemblement transversal")
      expect(response.body).to match(/gathering_team_ids_#{accueil.id}"[^>]*checked/)
    end
  end

  describe "l'index" do
    it "affiche les pôles en badges, et « Transversal » quand il n'y en a pas" do
      build_gathering(teams: [accueil], name: "Réunion du pôle")
      build_gathering(teams: [], name: "Assemblée générale")

      get gatherings_path

      expect(response.body).to include("Pôle Accueil")
      expect(response.body).to include("Transversal")
    end

    it "se filtre par pôle" do
      build_gathering(teams: [accueil], name: "Réunion Accueil")
      build_gathering(teams: [technique], name: "Réunion Technique")

      get gatherings_path(team_id: accueil.id)

      expect(response.body).to include("Réunion Accueil")
      expect(response.body).not_to include("Réunion Technique")
    end
  end

  describe "la fiche" do
    it "affiche les pôles concernés" do
      gathering = build_gathering(teams: [technique])

      get gathering_path(gathering)

      expect(response.body).to include("Pôles", "Pôle Technique")
    end
  end

  describe "le modèle" do
    it "refuse deux fois le même pôle sur le même rassemblement" do
      gathering = build_gathering(teams: [accueil])

      doublon = GatheringTeam.new(gathering: gathering, team: accueil)

      expect(doublon).not_to be_valid
      expect { doublon.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
