require "rails_helper"

# Feature 1 — « Gestion des rôles » par membre : un membre avec
# `roles_enabled: false` reste dans l'équipe mais disparaît des écrans
# d'assignation de rôles (veilleur, nourrissage…).
RSpec.describe "Humans — gestion des rôles activable", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-roles@les4sources.be", password: "password123") }
  before { sign_in user }

  describe "GET /roles/new (sélecteur de membres assignables à un rôle)" do
    it "ne propose que les membres dont la gestion des rôles est activée" do
      with_roles    = Human.create!(name: "Veilleur Assignable", roles_enabled: true)
      without_roles = Human.create!(name: "Sans Gestion Roles", roles_enabled: false)

      get new_role_path

      expect(response).to have_http_status(:ok)
      # On cible les cases à cocher du champ `role_team` : le layout
      # (avatars/tooltips) affiche légitimement tous les membres ailleurs sur la
      # page, donc on n'assertionne pas sur le nom brut.
      team_checkbox = ->(human) { /type="checkbox"[^>]*value="#{human.id}"[^>]*name="role\[role_team\]\[\]"/ }
      expect(response.body).to match(team_checkbox.call(with_roles))
      expect(response.body).not_to match(team_checkbox.call(without_roles))
    end
  end

  describe "édition d'un membre" do
    it "permet de désactiver la gestion des rôles via le formulaire" do
      human = Human.create!(name: "Membre A Restreindre", roles_enabled: true)

      patch human_path(human), params: { human: { name: human.name, roles_enabled: "0" } }

      expect(human.reload.roles_enabled).to be(false)
    end

    it "permet de désactiver le statut (membre inactif)" do
      human = Human.create!(name: "Membre A Desactiver", status: "active")

      patch human_path(human), params: { human: { name: human.name, status: "inactive" } }

      expect(Human.unscoped.find(human.id).status).to eq("inactive")
    end
  end
end
