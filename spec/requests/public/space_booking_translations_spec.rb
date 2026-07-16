require "rails_helper"

# Issue #15, Phase 3 — contenu traduit de la page espaces à jeton en NL et EN.
RSpec.describe "Page espaces client — contenu NL/EN", type: :request do
  let(:space) { Space.create!(name: "Grande Salle", capacity: 20) }
  let(:space_booking) do
    sb = SpaceBooking.create!(firstname: "Alex", lastname: "Durand",
                              from_date: Date.today + 5, to_date: Date.today + 6,
                              status: "confirmed", price_cents: 5_000,
                              payment_method: "bank_transfer", option_kitchenware: true)
    SpaceReservation.create!(space: space, space_booking: sb, date: Date.today + 5, duration: "day")
    sb
  end

  let(:url) { "/public/espaces/#{space_booking.token}" }

  it "rend la page en néerlandais avec ?locale=nl" do
    get "#{url}?locale=nl"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Uw reservering")   # heading
    expect(response.body).to include("Uw gegevens")      # your_details
    expect(response.body).to include("Uw betaling")      # payment_heading
    expect(response.body).to include("Uw reservering is bevestigd") # status_callout
    expect(response.body).not_to include("Votre réservation")
    expect(response.body).to include('lang="nl"')
  end

  it "rend la page en anglais avec ?locale=en" do
    get "#{url}?locale=en"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your booking")     # heading
    expect(response.body).to include("Your details")     # your_details
    expect(response.body).to include("Your payment")     # payment_heading
    expect(response.body).to include("Your booking is confirmed") # status_callout
    expect(response.body).not_to include("Votre réservation")
    expect(response.body).to include('lang="en"')
  end

  describe "plage de dates (SpaceBookingDecorator#date_range)" do
    it "reste en français sur la page FR" do
      get url
      expect(response.body).to include(" au ")
    end

    it "est localisée en néerlandais" do
      get "#{url}?locale=nl"
      expect(response.body).to match(/van .+ tot /)
    end

    it "est localisée en anglais" do
      get "#{url}?locale=en"
      expect(response.body).to match(/from .+ to /)
    end
  end

  describe "durée d'activité (SpaceBookingDecorator#duration)" do
    it "est traduite (journée → dag / day)" do
      get "#{url}?locale=nl"
      expect(response.body).to include("dag")

      get "#{url}?locale=en"
      expect(response.body).to include("day")
    end
  end
end
