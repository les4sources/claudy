require "rails_helper"

# Séjour VIDE (Michael, 2026-10-19) : l'équipe ouvre le séjour dès le premier
# contact, avant d'en connaître la composition. Il ne lui faut que des dates.
RSpec.describe "Stays — séjour vide", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-vide@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def params_vides(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: "", status: "pending"
      }.merge(overrides)
    }
  end

  it "crée un séjour sans aucune composition, daté par le formulaire, à 0 €" do
    expect { post stays_path, params: params_vides }.to change(Stay, :count).by(1)
    expect(response).to redirect_to(recent_stays_path)

    stay = Stay.order(:created_at).last
    expect(stay.stay_items).to be_empty
    expect(stay.experience_bookings).to be_empty
    expect(stay.meal_orders).to be_empty
    expect([stay.arrival_date, stay.departure_date]).to eq([arrival, departure])
    expect(stay.total_amount_cents).to eq(0)
    expect(stay.payment_status).to eq("pending")
  end

  it "accepte une journée (arrivée = départ)" do
    expect { post stays_path, params: params_vides(departure_date: arrival.iso8601) }.to change(Stay, :count).by(1)
  end

  it "refuse un séjour vide sans dates" do
    expect { post stays_path, params: params_vides(arrival_date: "", departure_date: "") }.not_to change(Stay, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Veuillez choisir les dates du séjour.")
  end

  it "refuse un départ avant l'arrivée" do
    expect { post stays_path, params: params_vides(departure_date: (arrival - 1).iso8601) }.not_to change(Stay, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "s'ouvre, se modifie et s'affiche sans composition" do
    post stays_path, params: params_vides
    stay = Stay.order(:created_at).last

    get edit_stay_path(stay)
    expect(response).to have_http_status(:ok)

    patch stay_path(stay), params: params_vides(customer_mode: "existing", customer_id: stay.customer_id,
                                                new_customer: {}, departure_date: (departure + 1).iso8601)
    expect(response).to redirect_to(recent_stays_path)
    expect(stay.reload.departure_date).to eq(departure + 1)

    get stay_path(stay)
    expect(response).to have_http_status(:ok)
    get public_stay_path(stay.token)
    expect(response).to have_http_status(:ok)
    get stays_path(status: "all")
    expect(response).to have_http_status(:ok)
    get root_path
    expect(response).to have_http_status(:ok)
  end
end
