require "rails_helper"

# Le fil « Activité récente » quitte le bas du calendrier pour sa page dédiée
# (menu Accueil → Activité récente, 2026-07-20).
RSpec.describe "Activité récente (/recent-activity)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "activity@les4sources.be", password: "password123") }

  before { sign_in user }

  it "rend la page dédiée avec le titre" do
    get "/recent-activity"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Activité récente")
  end

  it "le calendrier ne porte plus le fil d'activité" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Activité récente</h2>")
  end

  it "le menu Accueil contient le lien vers la page" do
    get "/"

    expect(response.body).to include("/recent-activity")
  end
end
