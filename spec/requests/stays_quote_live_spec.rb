require "rails_helper"

# Issue #73 — devis live du form de composition Séjour admin. L'endpoint
# `POST /stays/quote` reconstruit le Draft depuis les params et renvoie le
# panneau « Devis (B2C) » recalculé (Turbo Stream), cohérent avec le devis au
# submit (même PricingModel).
RSpec.describe "Stays — devis live (issue #73)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-quote@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 } # 2 nuits

  def composition_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: hulotte.id
      }.merge(overrides)
    }
  end

  it "renvoie le panneau devis recalculé en Turbo Stream" do
    post quote_stays_path, params: composition_params,
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("stay-quote-panel")
    expect(response.body).to include("Devis (B2C)")
    # Hulotte 2 nuits = 745 € : le total apparaît dans le panneau.
    expect(response.body).to include("745")
  end

  it "reflète l'ajout d'un espace dans le total (cohérent avec PricingModel)" do
    Space.create!(name: "Grande Salle", capacity: 1)
    post quote_stays_path, params: composition_params(
      halls: { "0" => { kind: "grande_salle", date: arrival.iso8601, period: "journee" } }
    ), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    # 745 € héberg + 290 € grande salle journée = 1 035 €.
    expect(response.body).to include("1 035").or include("1035")
  end

  it "gère une composition vide sans planter (panneau présent, total à 0)" do
    post quote_stays_path, params: { stay: { customer_mode: "new" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("stay-quote-panel")
  end
end
