require "rails_helper"

# Rôles d'accès (Michael, 2026-10-09) : chaque rôle n'ouvre que ses sections,
# la lecture seule refuse toute écriture, et une section non attribuée reste
# aux Sourciers.
RSpec.describe "Rôles d'accès", type: :request do
  include Devise::Test::IntegrationHelpers

  def account(email, roles)
    User.create!(email: email, password: "password123", access_roles: roles)
  end

  context "Kid" do
    before { sign_in account("kid@les4sources.be", %w[kid]) }

    it "lit le calendrier, sans les liens réservés aux Sourciers" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(">Comptabilité<")
      expect(response.body).not_to include(%(href="#{stays_path}))
    end

    it "lit la carte" do
      get map_path
      expect(response).to have_http_status(:ok)
    end

    it "ne modifie rien sur la carte" do
      post plants_path, params: { plant: { name: "Pommier" } }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(AccessControl::READ_ONLY)
    end

    it "est renvoyé vers le calendrier depuis une section fermée" do
      get stays_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(AccessControl::NO_ACCESS)
    end
  end

  context "Communication" do
    before { sign_in account("com@les4sources.be", %w[communication]) }

    it "gère les événements et les activités" do
      get events_path
      expect(response).to have_http_status(:ok)
      get experiences_path
      expect(response).to have_http_status(:ok)
    end

    it "n'ouvre pas la comptabilité" do
      get finance_accounting_path
      expect(response).to redirect_to(root_path)
    end
  end

  context "Administratif" do
    before { sign_in account("compta@les4sources.be", %w[administratif]) }

    it "ouvre la comptabilité et les comptes" do
      get finance_accounting_path
      expect(response).to have_http_status(:ok)
      get finance_accounts_path
      expect(response).to have_http_status(:ok)
    end

    it "n'ouvre pas la carte" do
      get map_path
      expect(response).to redirect_to(root_path)
    end
  end

  context "compte sans rôle" do
    before { sign_in account("nouveau@les4sources.be", []) }

    it "voit une page qui le lui dit, sans boucle de redirections" do
      get root_path
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("Pas encore d'accès")
    end
  end

  describe "Paramètres › Accès" do
    let(:sourcier) { account("michael@les4sources.be", %w[sourcier]) }
    let!(:autre) { account("kid@les4sources.be", %w[kid]) }

    it "est réservé aux Sourciers" do
      sign_in autre
      get access_roles_path
      expect(response).to redirect_to(root_path)
    end

    it "donne plusieurs rôles à un compte, ou les lui retire tous" do
      sign_in sourcier
      get access_roles_path
      expect(response).to have_http_status(:ok)

      patch access_roles_path, params: { users: { autre.id => ["", "kid", "communication"] } }
      expect(autre.reload.access_roles).to eq(%w[kid communication])

      patch access_roles_path, params: { users: { autre.id => [""] } }
      expect(autre.reload.access_roles).to eq([])
    end

    it "empêche un Sourcier de retirer son propre rôle" do
      sign_in sourcier
      patch access_roles_path, params: { users: { sourcier.id => ["", "kid"] } }
      expect(sourcier.reload.access_roles).to eq(%w[sourcier])
      expect(flash[:alert]).to include("propre rôle de Sourcier")
    end
  end
end
