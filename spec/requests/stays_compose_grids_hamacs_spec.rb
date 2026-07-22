require "rails_helper"

# Slice C — le frame `stay_compose_grids` (rechargé au changement de dates)
# rend TOUTES les grilles datées, dont les HAMACS (parité funnel, devis seul).
# Sans dates : état vide clair « choisissez d'abord les dates ».
RSpec.describe "Stays — grilles de composition (frame compose_grids)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-grids@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  let!(:hulotte) { Lodging.create!(name: "La Hulotte", summary: "gîte") }

  it "inclut les steppers hamacs (simple + double) quand des dates sont fournies" do
    get compose_grids_stays_path, params: { arrival_date: arrival.iso8601, departure_date: departure.iso8601 }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="stay[per_night_resources][hamac_simple][]"')
    expect(response.body).to include('name="stay[per_night_resources][hamac_double][]"')
    expect(response.body).to include("Location de hamacs")
  end

  it "inclut la grille hébergement nuit par nuit (param_root stay) quand des dates sont fournies" do
    get compose_grids_stays_path, params: { arrival_date: arrival.iso8601, departure_date: departure.iso8601 }
    expect(response.body).to include('data-public--stay-calendar-param-root-value="stay"')
    expect(response.body).to include(hulotte.name)
  end

  it "affiche un état vide sans dates (pas de steppers hamacs)" do
    get compose_grids_stays_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('name="stay[per_night_resources][hamac_simple][]"')
    expect(response.body).to include("Choisissez d'abord les dates")
  end
end
