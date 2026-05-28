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
end
