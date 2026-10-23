require "rails_helper"

# Séjour « activité seule » (Michael, 2026-10-13) : un groupe venu à la journée
# pour un atelier, sans hébergement ni espace, n'avait aucun réservable à
# dessiner et n'apparaissait jamais au calendrier. Il y a désormais son bloc, au
# jour de son activité. Un séjour qui a déjà un réservable garde son bloc
# habituel, sans chip d'activité.
RSpec.describe "Calendrier — séjour activité seule", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-activite-seule@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:day) { Date.today.beginning_of_month + 14 }
  let(:experience) { Experience.create!(name: "Atelier pizza", duration_hours: 2) }
  let!(:slot) { experience.experience_availabilities.create!(available_on: day, starts_at: "14:00") }
  let(:customer) do
    Customers::UpsertByEmail.call(email: "c.degraef@frw.be", attrs: { organization_name: "Fédération Rurale de Wallonie" })
  end

  def stay_with_activity(status: "pending", booking_status: "pending")
    stay = Stay.create!(customer: customer, source: "manual", status: status, arrival_date: day, departure_date: day)
    ExperienceBooking.create!(stay: stay, experience_availability: slot, participants: 8, status: booking_status)
    stay
  end

  it "dessine un bloc pour le séjour, au jour de son activité" do
    stay = stay_with_activity

    get "/", params: { date: day.iso8601 }

    expect(response).to have_http_status(:ok)
    expect(response.body.scan("data-stay-id=\"#{stay.id}\"").size).to eq(1)
    expect(response.body).to include("🎯 Atelier pizza · 14:00 · 8 pers.")
    expect(response.body).to include("href=\"#{stay_path(stay)}\"")
  end

  it "ne dessine rien pour un séjour annulé, ni l'activité annulée d'un séjour vivant" do
    canceled = stay_with_activity(status: "canceled")
    dropped = stay_with_activity(booking_status: "cancelled")

    get "/", params: { date: day.iso8601 }

    expect(response.body).not_to include("data-stay-id=\"#{canceled.id}\"")
    # Le séjour dont l'activité est annulée reste vivant : c'est désormais un
    # séjour vide (Michael, 2026-10-23), posé sur ses dates sans chip d'activité.
    expect(response.body.scan("data-stay-id=\"#{dropped.id}\"").size).to eq(1)
    expect(response.body).not_to include("🎯 Atelier pizza")
    expect(response.body).to include("Composition à définir")
  end

  it "laisse inchangé le bloc d'un séjour qui a déjà un espace" do
    stay = stay_with_activity
    space = Space.create!(name: "Grande Salle", code: "GS", capacity: 40)
    space_booking = SpaceBooking.create!(firstname: "FRW", group_name: "FRW", from_date: day, to_date: day, status: "pending")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: day)
    StayItem.create!(stay: stay, bookable: space_booking)

    get "/", params: { date: day.iso8601 }

    expect(response.body.scan("data-stay-id=\"#{stay.id}\"").size).to eq(1)
    expect(response.body).not_to include("🎯 Atelier pizza")
  end
end
