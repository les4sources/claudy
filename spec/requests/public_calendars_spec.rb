require "rails_helper"

# Calendrier de disponibilité PUBLIC (sans Devise) — embarqué en iframe sur le
# site des 4 Sources. Smoke test de rendu : cette page a déjà été cassée en prod
# (500) par une erreur d'indentation Slim (pills hors du bloc each → NameError)
# passée inaperçue faute de couverture. Plus jamais.
RSpec.describe "Public — calendrier de disponibilité", type: :request do
  let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte", available_for_bookings: true) }
  let!(:space)   { Space.create!(name: "Grande Salle", capacity: 10) }

  it "rend la page sans authentification, avec hébergements et espaces" do
    get "/public/calendrier-hebergements"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("La Hulotte")
    expect(response.body).to include("Grande Salle")
  end

  it "rend la modale du calendrier" do
    get "/public/calendar-lodgings-modal", params: { date: (Date.today + 7).iso8601 }

    expect(response).to have_http_status(:ok)
  end
end
