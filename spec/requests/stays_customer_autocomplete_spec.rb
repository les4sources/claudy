require "rails_helper"

# Issue #74 — autocomplete client dans le form de composition Séjour admin.
# Réutilise l'endpoint existant customers/search (JSON) ; le form câble un champ
# de recherche piloté par le contrôleur Stimulus customer-search, avec fallback
# <select> sans-JS.
RSpec.describe "Stays — autocomplete client (issue #74)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-autocomplete@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  describe "GET /customers/search" do
    it "renvoie le JSON attendu { id, name, email }" do
      Customer.create!(first_name: "Zoé", last_name: "Dupont", email: "zoe@example.com", customer_type: "individual")
      get search_customers_path, params: { q: "Zoé" }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.first).to include("id", "name", "email")
      expect(body.first["email"]).to eq("zoe@example.com")
    end
  end

  describe "POST /stays avec un client sélectionné (customer_id)" do
    it "rattache le séjour au bon client" do
      customer = Customer.create!(first_name: "Alice", last_name: "Martin", email: "alice@example.com", customer_type: "individual")

      post stays_path, params: {
        stay: {
          customer_mode: "existing", customer_id: customer.id, new_customer: {},
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0, lodging_id: hulotte.id, status: "pending"
        }
      }
      expect(response).to redirect_to(recent_stays_path)
      expect(Stay.order(:created_at).last.customer).to eq(customer)
    end
  end

  describe "câblage du form" do
    it "le form new expose la recherche client (controller + select fallback)" do
      get new_stay_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="customer-search"')
      expect(response.body).to include("customer-search-target=\"select\"")
      expect(response.body).to include("customer-search-target=\"searchInput\"")
      expect(response.body).to include(search_customers_path)
    end

    it "le form edit pré-affiche le client courant dans le <select> de repli" do
      customer = Customer.create!(first_name: "Bob", last_name: "Durand", email: "bob@example.com", customer_type: "individual")
      stay = Stay.create!(customer: customer, source: "manual", status: "pending",
                          arrival_date: arrival, departure_date: departure, total_amount_cents: 0)

      get edit_stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("selected=\"selected\" value=\"#{customer.id}\"")
    end
  end
end
