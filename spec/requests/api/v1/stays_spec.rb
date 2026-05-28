require "rails_helper"

RSpec.describe "Api::V1::Stays", type: :request do
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

  let!(:customer) { Customer.create!(email: "stayapi@example.com", customer_type: "individual") }
  let!(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 7, 1),
                 departure_date: Date.new(2026, 7, 3), status: "confirmed")
  end
  let!(:booking) do
    Booking.create!(firstname: "Stay", from_date: Date.new(2026, 7, 1), to_date: Date.new(2026, 7, 3),
                    adults: 1, status: "confirmed")
  end

  before { stay.stay_items.create!(bookable: booking) }

  describe "GET /api/v1/stays" do
    it "lists stays with pagination meta" do
      get "/api/v1/stays", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"]).to be_an(Array)
      expect(json["meta"]).to include("page", "per_page", "total")
    end

    it "filters by customer_id" do
      other = Customer.create!(email: "other-stay@example.com", customer_type: "individual")
      Stay.create!(customer: other, arrival_date: Date.new(2026, 9, 1), departure_date: Date.new(2026, 9, 2))
      get "/api/v1/stays", params: { customer_id: customer.id }, headers: auth
      expect(json["data"].map { |s| s["id"] }).to contain_exactly(stay.id)
    end
  end

  describe "GET /api/v1/stays/:id" do
    it "exposes the polymorphic items with their concrete type" do
      get "/api/v1/stays/#{stay.id}", headers: auth
      expect(response).to have_http_status(:ok)
      item = json["data"]["items"].first
      expect(item["bookable_type"]).to eq("Booking")
      expect(item["bookable_id"]).to eq(booking.id)
    end

    it "returns 404 for a soft-deleted stay (AC-30)" do
      stay.soft_delete!(validate: false)
      get "/api/v1/stays/#{stay.id}", headers: auth
      expect(response).to have_http_status(:not_found)
    end
  end
end
