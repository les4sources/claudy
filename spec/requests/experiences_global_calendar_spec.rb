require "rails_helper"

# Epic #25, Phase 5 — calendrier global au-dessus du tableau des activités.
RSpec.describe "Experiences — calendrier global de l'index", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:monday) { Date.today.beginning_of_week(:monday) }
  let(:balade) { Experience.create!(name: "Balade avec les ânes", duration_hours: 2) }
  let(:poterie) { Experience.create!(name: "Atelier poterie", duration_hours: 3) }

  before { sign_in user }

  it "rend le calendrier même sans aucun créneau" do
    balade

    get experiences_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-global-week-calendar")
    expect(response.body).to include("Aucun créneau posé cette semaine")
  end

  it "affiche les créneaux de la semaine en cours, toutes activités confondues" do
    ExperienceAvailability.create!(experience: balade, available_on: monday + 1, starts_at: "10:00")
    ExperienceAvailability.create!(experience: poterie, available_on: monday + 2, starts_at: "14:00")

    get experiences_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-global-slot=\"#{(monday + 1).iso8601} 10:00\"")
    expect(response.body).to include("data-global-slot=\"#{(monday + 2).iso8601} 14:00\"")
    expect(response.body).to include("10:00→12:00")
    expect(response.body).to include("14:00→17:00")
  end

  it "donne à chaque activité sa couleur (style inline, pas de classe Tailwind)" do
    ExperienceAvailability.create!(experience: balade, available_on: monday + 1, starts_at: "10:00")

    get experiences_path

    expect(response.body).to include(balade.reload.color)
    expect(response.body).to include("data-calendar-legend")
  end

  it "affiche les créneaux qui se chevauchent entre deux activités" do
    ExperienceAvailability.create!(experience: balade, available_on: monday + 3, starts_at: "10:00")
    ExperienceAvailability.create!(experience: poterie, available_on: monday + 3, starts_at: "10:00")

    get experiences_path

    expect(response.body.scan("data-global-slot=\"#{(monday + 3).iso8601} 10:00\"").size).to eq(2)
  end

  it "navigue vers une autre semaine via ?week=" do
    ExperienceAvailability.create!(experience: balade, available_on: monday + 8, starts_at: "10:00")

    get experiences_path(week: (monday + 7).iso8601)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-global-slot=\"#{(monday + 8).iso8601} 10:00\"")
    expect(response.body).to include("Aujourd&#39;hui") # retour à la semaine en cours proposé
  end

  it "ignore un ?week= illisible et retombe sur la semaine en cours" do
    ExperienceAvailability.create!(experience: balade, available_on: monday + 1, starts_at: "10:00")

    get experiences_path(week: "pas-une-date")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-global-slot=\"#{(monday + 1).iso8601} 10:00\"")
  end
end
