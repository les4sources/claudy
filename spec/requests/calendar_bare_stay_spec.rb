require "rails_helper"

# Séjour sans réservable (Michael, 2026-10-23) : depuis la PR #544, un séjour
# peut naître vide (client + dates). Sans hébergement, espace ni activité, il
# n'avait aucun bloc au calendrier. Il est désormais posé sur ses propres nuits
# [arrivée, départ), ou sur son seul jour s'il tient en une journée.
RSpec.describe "Calendrier — séjour sans réservable", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-sejour-vide@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:day) { Date.today.beginning_of_month + 10 }
  let(:customer) do
    Customers::UpsertByEmail.call(email: "alice@example.com", attrs: { first_name: "Alice", last_name: "Martin" })
  end

  def bare_stay(arrival: day, departure: day + 2, status: "pending")
    Stay.create!(customer: customer, source: "manual", status: status, arrival_date: arrival, departure_date: departure)
  end

  def blocks_of(stay)
    response.body.scan("data-stay-id=\"#{stay.id}\"").size
  end

  it "dessine un bloc par nuit pour un séjour vide, sans chip" do
    stay = bare_stay

    get "/", params: { date: day.iso8601 }

    expect(response).to have_http_status(:ok)
    expect(blocks_of(stay)).to eq(2)
    expect(response.body).not_to include("Composition à définir")
    expect(response.body).to include("href=\"#{stay_path(stay)}\"")
  end

  it "dessine un seul bloc pour un séjour d'une journée" do
    stay = bare_stay(departure: day)

    get "/", params: { date: day.iso8601 }

    expect(blocks_of(stay)).to eq(1)
  end

  it "ne dessine rien pour un séjour vide annulé" do
    stay = bare_stay(status: "canceled")

    get "/", params: { date: day.iso8601 }

    expect(blocks_of(stay)).to eq(0)
  end

  it "montre les repas du jour d'un séjour qui n'a que des repas" do
    stay = bare_stay(departure: day)
    MealOrder.create!(stay: stay, kind: "repas", moment: "midi", date: day, people: 12, skip_notifications: true)

    get "/", params: { date: day.iso8601 }

    expect(blocks_of(stay)).to eq(1)
    expect(response.body).to include("🍽 Midi · 12 pers.")
  end

  it "laisse au séjour qui a une activité son seul bloc d'activité" do
    stay = bare_stay
    experience = Experience.create!(name: "Atelier pizza", duration_hours: 2)
    slot = experience.experience_availabilities.create!(available_on: day, starts_at: "14:00")
    ExperienceBooking.create!(stay: stay, experience_availability: slot, participants: 8, status: "pending")

    get "/", params: { date: day.iso8601 }

    expect(blocks_of(stay)).to eq(1)
    expect(response.body).to include("🎯 Atelier pizza")
  end

  it "le reprend dans le bandeau « Aujourd'hui » le jour de son arrivée" do
    stay = bare_stay(arrival: Date.today, departure: Date.today + 1)

    get "/"

    expect(response.body).to include("data-today-stay-card=\"#{stay.id}\"")
  end
end
