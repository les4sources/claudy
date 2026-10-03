require "rails_helper"

# Reporting › Site web (2026-10-03).
RSpec.describe "Reporting — statistiques du site", type: :request do
  include Devise::Test::IntegrationHelpers

  it "demande une connexion" do
    get site_stats_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "affiche le tableau de bord à un membre connecté, avec les pages vues" do
    sign_in User.create!(email: "stats@les4sources.be", password: "password123")
    SiteHit.create!(kind: "pageview", path: "/sejours/tarifs", visitor_hash: "v1", source: "Google",
                    occurred_at: Time.current, day: Time.zone.today, device: "Mobile")

    get site_stats_path(period: "7")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Statistiques du site web", "/sejours/tarifs", "Google", "Entonnoir de réservation")
  end

  it "affiche un état vide lisible" do
    sign_in User.create!(email: "stats-vide@les4sources.be", password: "password123")

    get site_stats_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aucune visite enregistrée sur cette période.")
  end
end
