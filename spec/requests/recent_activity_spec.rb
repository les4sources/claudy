require "rails_helper"

# Le fil « Activité récente » quitte le bas du calendrier pour sa page dédiée
# (menu Accueil → Activité récente, 2026-07-20).
RSpec.describe "Activité récente (/recent-activity)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "activity@les4sources.be", password: "password123") }

  before { sign_in user }

  it "rend la page dédiée avec le titre ET le contenu du fil" do
    booking = Booking.create!(firstname: "Feed", from_date: Date.today + 10, to_date: Date.today + 11,
                              adults: 1, status: "pending", price_cents: 0)
    PublicActivity::Activity.create!(trackable: booking, key: "booking.create", created_at: 1.day.ago)

    get "/recent-activity"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Activité récente")
    # Le fil n'est pas vide (l'action contrôleur doit charger @activities —
    # bug du 2026-07-20 : action perdue, page rendue avec un fil nil).
    expect(response.body).to include("Feed")
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
