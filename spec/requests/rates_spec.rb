require "rails_helper"

# Issue #124 — écran Paramètres > Tarifs.
RSpec.describe "Paramètres > Tarifs", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  before do
    sign_in user
    Rates::SeedFromCatalog.new.run
  end

  describe "GET /rates" do
    it "liste les tarifs groupés par domaine dans le menu paramètres" do
      get rates_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tarifs")
      expect(response.body).to include("Hébergements")
      expect(response.body).to include("Salles")
      expect(response.body).to include("Camping &amp; van")
      expect(response.body).to include("Repas")
      expect(response.body).to include("Divers")
      expect(response.body).to include("van.per_night")
      # menu secondaire paramètres présent
      expect(response.body).to include("Expériences")
    end

    it "affiche un montant en euros et un taux en pourcentage" do
      get rates_path

      expect(response.body).to include('value="15.0"')  # van : 15 €/nuit
      expect(response.body).to include('value="50"')    # acompte : 50 %
    end
  end

  describe "PATCH /rates/:id" do
    let(:van) { Rate.find_by(key: "van.per_night") }

    it "met à jour le montant en convertissant les euros en cents" do
      patch rate_path(van), params: { rate: { amount: "18,50" } }

      expect(response).to redirect_to(rates_path)
      expect(van.reload.amount_cents).to eq(1_850)
      follow_redirect!
      expect(response.body).to include("a été mis à jour")
    end

    it "met à jour un taux en points de pourcentage" do
      deposit = Rate.find_by(key: "deposit.default_rate")
      patch rate_path(deposit), params: { rate: { amount: "30" } }

      expect(deposit.reload.amount_cents).to eq(30)
    end

    it "refuse un montant négatif et laisse le tarif intact" do
      patch rate_path(van), params: { rate: { amount: "-5" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(van.reload.amount_cents).to eq(1_500)
    end

    it "refuse une saisie non numérique" do
      patch rate_path(van), params: { rate: { amount: "gratuit" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(van.reload.amount_cents).to eq(1_500)
    end
  end

  describe "sans authentification" do
    it "redirige vers la connexion" do
      sign_out user
      get rates_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
