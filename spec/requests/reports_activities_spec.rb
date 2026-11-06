require "rails_helper"

RSpec.describe "Reporting — activités", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "reporting-activites@les4sources.be", password: "password123") }

  before { sign_in user }

  it "affiche les activités de l'année, par activité et par mois" do
    customer = Customer.create!(email: "activites-page@example.com", customer_type: "individual")
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed")
    experience = Experience.create!(name: "Grimpe test", fixed_price_cents: 6_000, price_cents: 0)
    availability = ExperienceAvailability.create!(experience: experience, available_on: Date.new(2026, 5, 21),
                                                  starts_at: "09:30")
    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 10, status: "confirmed")

    get activity_reports_path(year: 2026)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reporting des activités (2026)")
    expect(response.body).to include("Grimpe test")
    expect(response.body).to include("Mai 2026")
  end

  it "reste lisible sur une année sans activité" do
    get activity_reports_path(year: 2019)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aucune activité confirmée en 2019.")
  end

  it "est accessible depuis la sous-navigation du reporting" do
    get reports_path(year: 2026)

    expect(response.body).to include(activity_reports_path)
  end
end
