require "rails_helper"

# Calendrier global MENSUEL de /experiences (2026-07-20, remplace la vue
# semaine de l'epic #25) : une ligne par activité, un badge « nombre de
# créneaux » par jour — jamais le détail des créneaux.
RSpec.describe "Experiences — calendrier global de l'index", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:month) { Date.today.next_month.beginning_of_month }
  let(:balade) { Experience.create!(name: "Balade avec les ânes", duration_hours: 2) }
  let(:poterie) { Experience.create!(name: "Atelier poterie", duration_hours: 3) }

  before { sign_in user }

  it "rend le calendrier même sans aucun créneau" do
    balade

    get experiences_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Créneaux du mois")
    expect(response.body).to include("Aucun créneau posé ce mois-ci")
  end

  it "affiche une ligne par activité avec le NOMBRE de créneaux par jour, pas le détail" do
    2.times { |i| ExperienceAvailability.create!(experience: balade, available_on: month + 3, starts_at: "#{10 + i * 3}:00") }
    ExperienceAvailability.create!(experience: poterie, available_on: month + 5, starts_at: "14:00")

    get experiences_path, params: { month: month.strftime("%Y-%m") }

    expect(response.body).to include("Balade avec les ânes")
    expect(response.body).to include("Atelier poterie")
    expect(response.body).to match(/2 créneaux le/)   # badge + tooltip
    expect(response.body).not_to include("10:00→")    # aucun détail de créneau
  end

  it "le nom d'activité en tête de ligne pointe vers sa fiche, dans une cellule sticky" do
    ExperienceAvailability.create!(experience: balade, available_on: month + 3, starts_at: "10:00")

    get experiences_path, params: { month: month.strftime("%Y-%m") }

    row_header = response.body[/<th[^>]*sticky[^>]*scope="row".*?<\/th>/m]
    expect(row_header).to include(experience_path(balade))
    expect(row_header).to include("Balade avec les ânes")
  end

  it "navigue vers un autre mois via ?month=" do
    target = month.next_month
    ExperienceAvailability.create!(experience: balade, available_on: target + 4, starts_at: "10:00")

    get experiences_path, params: { month: target.strftime("%Y-%m") }

    expect(response.body).to include(I18n.l(target, format: "%B %Y").capitalize)
    expect(response.body).to include("Balade avec les ânes")
  end

  it "ignore un ?month= illisible et retombe sur le mois courant" do
    get experiences_path, params: { month: "grumpf" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.l(Date.today.beginning_of_month, format: "%B %Y").capitalize)
  end

  it "n'affiche pas de ligne pour une activité sans créneau dans le mois affiché" do
    poterie
    ExperienceAvailability.create!(experience: balade, available_on: month + 3, starts_at: "10:00")

    get experiences_path, params: { month: month.strftime("%Y-%m") }

    grid = response.body[/Créneaux du mois.*?<\/table>/m]
    expect(grid).to include("Balade avec les ânes")
    expect(grid).not_to include("Atelier poterie")
  end
end
