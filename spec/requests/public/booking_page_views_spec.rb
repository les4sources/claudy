require "rails_helper"

# issue #16 — suivi des consultations de la page web privée du client.
RSpec.describe "Suivi des consultations de la page de réservation", type: :request do
  let!(:booking) do
    Booking.create!(firstname: "Vue", lastname: "Client", from_date: Date.today,
                    to_date: Date.today + 2, adults: 2, children: 0, babies: 0,
                    status: "confirmed", price_cents: 0, token: "tok-views-123")
  end

  describe "GET /public/reservation/:token" do
    it "enregistre une consultation" do
      expect {
        get public_booking_path(booking.token)
      }.to change { booking.page_views.count }.by(1)
      expect(response).to have_http_status(:ok)
    end

    it "n'enregistre rien avec ?donottrack et nettoie l'URL côté client" do
      expect {
        get public_booking_path(booking.token), params: { donottrack: "1" }
      }.not_to change { booking.page_views.count }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("history.replaceState")
    end

    it "renvoie 404 pour un jeton inconnu sans rien enregistrer" do
      expect {
        get public_booking_path("jeton-inexistant")
      }.not_to change(BookingPageView, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /bookings/:id (admin)" do
    include Devise::Test::IntegrationHelpers
    let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
    before { sign_in user }

    it "affiche la carte des statistiques de consultation" do
      booking.page_views.create!(ip_address: "1.1.1.1", user_agent: "RSpec")
      get booking_path(booking)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Consultations de la page client")
    end
  end
end
