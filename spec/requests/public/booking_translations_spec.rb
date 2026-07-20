require "rails_helper"

# Issue #15, Phase 2 — contenu traduit de la page booking à jeton en NL et EN.
RSpec.describe "Page booking client — contenu NL/EN", type: :request do
  # Dates ancrées DANS un seul mois futur (jours 10 → 12) : avec `Date.today + 10`,
  # la plage chevauchait parfois deux mois et `date_range` affichait le mois aux
  # deux bornes — les regex « du \d+ au » devenaient flaky selon le jour du run.
  let(:booking) do
    month = (Date.today + 40).beginning_of_month
    Booking.create!(firstname: "Alex", lastname: "Durand", from_date: month + 9,
                    to_date: month + 11, adults: 2, children: 1, babies: 0, status: "confirmed",
                    booking_type: "lodging", price_cents: 48_500)
  end

  let(:url) { "/public/reservation/#{booking.token}" }

  it "rend la page en néerlandais avec ?locale=nl" do
    get "#{url}?locale=nl"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Uw reservering")     # heading
    expect(response.body).to include("Uw gegevens")        # your_details
    expect(response.body).to include("Uw aankomst")        # arrival_heading
    expect(response.body).to include("Mee te nemen")       # packing_heading
    expect(response.body).to include("Bijwerken")          # bouton heure d'arrivée
    expect(response.body).not_to include("Votre réservation")
    expect(response.body).not_to include("Mettre à jour")
    expect(response.body).to include('lang="nl"')
  end

  it "rend la page en anglais avec ?locale=en" do
    get "#{url}?locale=en"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your booking")       # heading
    expect(response.body).to include("Your details")       # your_details
    expect(response.body).to include("Your arrival")       # arrival_heading
    expect(response.body).to include("What to bring")      # packing_heading
    expect(response.body).to include("Update")             # bouton heure d'arrivée
    expect(response.body).not_to include("Votre réservation")
    expect(response.body).not_to include("Mettre à jour")
    expect(response.body).to include('lang="en"')
  end

  describe "plage de dates (BookingDecorator#date_range)" do
    it "reste en français sur la page FR" do
      get url
      expect(response.body).to match(/du \d+ au /)
    end

    it "est localisée en néerlandais" do
      get "#{url}?locale=nl"
      expect(response.body).to match(/van \d+ tot /)
      expect(response.body).not_to match(/du \d+ au /)
    end

    it "est localisée en anglais" do
      get "#{url}?locale=en"
      expect(response.body).to match(/from \d+ to /)
      expect(response.body).not_to match(/du \d+ au /)
    end
  end
end
