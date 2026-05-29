require "rails_helper"

RSpec.describe "Customers (admin Pôle Accueil)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:customer) do
    Customer.create!(email: "admin@example.com", first_name: "Admin", last_name: "Client",
                     customer_type: "individual")
  end

  describe "GET /customers" do
    it "lists customers and supports search" do
      Customer.create!(email: "needle@example.com", first_name: "Needle", customer_type: "individual")
      get customers_path, params: { q: "needle" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("needle@example.com")
    end
  end

  describe "GET /customers/:id" do
    it "renders the customer page" do
      get customer_path(customer)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /customers/:id/edit + PATCH update" do
    it "updates the internal notes" do
      get edit_customer_path(customer)
      expect(response).to have_http_status(:ok)

      patch customer_path(customer), params: { customer: { notes: "Note Pôle Accueil" } }
      expect(response).to redirect_to(customer_path(customer))
      expect(customer.reload.notes.to_plain_text).to include("Note Pôle Accueil")
    end
  end

  describe "merge flow" do
    let!(:source) { Customer.create!(email: "merge-source@example.com", customer_type: "individual") }
    let!(:target) { Customer.create!(email: "merge-target@example.com", customer_type: "individual") }

    before do
      Stay.create!(customer: source, arrival_date: Date.today + 1, departure_date: Date.today + 2)
    end

    it "previews the merge" do
      get merge_preview_customer_path(source), params: { target_id: target.id }
      expect(response).to have_http_status(:ok)
    end

    it "commits the merge through the service" do
      post merge_commit_customer_path(source), params: { target_id: target.id }
      expect(response).to redirect_to(customer_path(target))
      expect(target.stays.count).to eq(1)
      expect(Customer.find_by(id: source.id)).to be_nil # source soft-deleted
    end
  end

  describe "GET /customers/search (autocomplete JSON)" do
    it "returns matching customers as JSON" do
      Customer.create!(email: "michael@semisto.org", first_name: "Michael", last_name: "Hulet", customer_type: "individual")
      Customer.create!(email: "autre@example.com", first_name: "Autre", customer_type: "individual")

      get search_customers_path, params: { q: "hulet" }
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.map { |c| c["email"] }).to include("michael@semisto.org")
      expect(data.map { |c| c["email"] }).not_to include("autre@example.com")
      expect(data.first).to include("id", "name", "email")
    end
  end

  describe "re-ventilation (reassign) from the catch-all" do
    let!(:catch_all) { Customer.create!(email: Customer::CATCH_ALL_EMAIL, first_name: "Client", customer_type: "individual") }
    let!(:keep) { Stay.create!(customer: catch_all, arrival_date: Date.today + 1, departure_date: Date.today + 2) }
    let!(:move) { Stay.create!(customer: catch_all, arrival_date: Date.today + 4, departure_date: Date.today + 5) }

    it "renders the show page with selectable stays and the modal" do
      get customer_path(catch_all)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("stay_ids[]")
      expect(response.body).to include("Assigner la sélection à un client")
    end

    it "renders enriched stay rows (French date, colored status label, contact, details link)" do
      enriched = Stay.create!(customer: catch_all, arrival_date: Date.new(2026, 2, 14),
                              departure_date: Date.new(2026, 2, 15), status: "confirmed")
      booking = Booking.create!(firstname: "Jean", lastname: "Dupont", group_name: "Les Amis",
                                from_date: Date.new(2026, 2, 14), to_date: Date.new(2026, 2, 15),
                                adults: 2, status: "confirmed")
      enriched.stay_items.create!(bookable: booking)

      get customer_path(catch_all)
      expect(response.body).to include("14 février 2026")
      expect(response.body).to include("Confirmé")
      expect(response.body).to include("bg-green-100") # label coloré, pas gris
      expect(response.body).to include("Jean Dupont")
      expect(response.body).to include(stay_path(enriched)) # bouton Détails
    end

    it "assigns selected stays to an existing customer (AC-53)" do
      target = Customer.create!(email: "real@example.com", customer_type: "individual")
      post reassign_customer_path(catch_all), params: { stay_ids: [move.id], target_id: target.id, mode: "existing" }
      expect(response).to redirect_to(customer_path(catch_all))
      expect(target.stays.reload).to contain_exactly(move)
      expect(catch_all.stays.reload).to contain_exactly(keep) # catch-all stays active
    end

    it "creates a new customer on the fly and assigns the stays (AC-54)" do
      expect {
        post reassign_customer_path(catch_all),
             params: { stay_ids: [move.id], mode: "new",
                       new_customer: { email: "fresh@example.com", first_name: "Fresh", customer_type: "individual" } }
      }.to change(Customer, :count).by(1)
      created = Customer.find_by(email: "fresh@example.com")
      expect(created.stays).to contain_exactly(move)
    end

    it "is a no-op when nothing is selected (AC-52)" do
      post reassign_customer_path(catch_all), params: { stay_ids: [], target_id: catch_all.id }
      expect(response).to redirect_to(customer_path(catch_all))
      expect(catch_all.stays.reload.count).to eq(2)
    end

    it "transfers nothing when the new customer email is invalid (AC-54 atomic)" do
      Customer.create!(email: "taken@example.com", customer_type: "individual")
      expect {
        post reassign_customer_path(catch_all),
             params: { stay_ids: [move.id], mode: "new",
                       new_customer: { email: "taken@example.com", customer_type: "individual" } }
      }.not_to change(Customer, :count)
      expect(move.reload.customer_id).to eq(catch_all.id)
      expect(flash[:alert]).to be_present
    end
  end
end
