require "rails_helper"

RSpec.describe "Api::V1::Customers", type: :request do
  let(:token) { "test-token-123" }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }

  around do |example|
    previous = ENV["AGENT_API_TOKEN"]
    ENV["AGENT_API_TOKEN"] = token
    example.run
    ENV["AGENT_API_TOKEN"] = previous
  end

  def json
    JSON.parse(response.body)
  end

  let!(:customer) do
    Customer.create!(email: "api@example.com", first_name: "Api", last_name: "Client",
                     customer_type: "individual", phone: "+32470111111")
  end

  describe "GET /api/v1/customers" do
    it "lists customers with pagination meta" do
      get "/api/v1/customers", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"]).to be_an(Array)
      expect(json["meta"]).to include("page", "per_page", "total")
    end

    it "filters by search query" do
      Customer.create!(email: "other@example.com", customer_type: "individual")
      get "/api/v1/customers", params: { q: "api@example.com" }, headers: auth
      emails = json["data"].map { |c| c["email"] }
      expect(emails).to include("api@example.com")
      expect(emails).not_to include("other@example.com")
    end

    it "requires authentication" do
      get "/api/v1/customers"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/customers/:id" do
    it "returns the customer and never exposes internal notes (§11.7)" do
      customer.update!(notes: "NOTE-INTERNE-SECRETE")
      get "/api/v1/customers/#{customer.id}", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"]["email"]).to eq("api@example.com")
      expect(json["data"]).not_to have_key("notes")
      expect(response.body).not_to include("NOTE-INTERNE-SECRETE")
    end

    it "returns 404 for a soft-deleted customer (AC-30)" do
      customer.soft_delete!(validate: false)
      get "/api/v1/customers/#{customer.id}", headers: auth
      expect(response).to have_http_status(:not_found)
    end

    it "is read-only: no create route is exposed" do
      expect { post "/api/v1/customers", headers: auth }.to raise_error(ActionController::RoutingError)
    end
  end
end
