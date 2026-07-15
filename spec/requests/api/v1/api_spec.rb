require "rails_helper"

RSpec.describe "Api::V1", type: :request do
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

  describe "authentication" do
    it "rejects requests without a token" do
      get "/api/v1/bookings"
      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("unauthorized")
    end

    it "rejects an invalid token" do
      get "/api/v1/bookings", headers: { "Authorization" => "Bearer nope" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts a valid token" do
      get "/api/v1/bookings", headers: auth
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1 (discovery index)" do
    it "lists resources and links to the spec" do
      get "/api/v1", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["resources"].map { |r| r["name"] }).to include("bookings", "availability", "payments")
      expect(json["documentation"]["openapi"]).to be_present
    end
  end

  describe "GET /api/v1/openapi" do
    it "serves the OpenAPI 3 spec as JSON" do
      get "/api/v1/openapi", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["openapi"]).to start_with("3.")
      expect(json.dig("paths", "/bookings")).to be_present
    end
  end

  describe "GET /api/v1/bookings" do
    let!(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }
    let!(:confirmed) do
      Booking.create!(firstname: "Alice", lastname: "Martin", from_date: Date.new(2026, 7, 1),
                      to_date: Date.new(2026, 7, 5), adults: 2, status: "confirmed",
                      lodging: lodging, price_cents: 40_000)
    end
    let!(:pending_booking) do
      Booking.create!(firstname: "Bob", from_date: Date.new(2026, 8, 1), to_date: Date.new(2026, 8, 3),
                      adults: 1, status: "pending")
    end

    it "returns paginated bookings with meta" do
      get "/api/v1/bookings", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"]).to be_an(Array)
      expect(json["meta"]).to include("page", "per_page", "total", "pages")
    end

    it "filters by status" do
      get "/api/v1/bookings", params: { status: "confirmed" }, headers: auth
      names = json["data"].map { |b| b["firstname"] }
      expect(names).to include("Alice")
      expect(names).not_to include("Bob")
    end

    it "filters by date range" do
      get "/api/v1/bookings", params: { from_date: "2026-07-15" }, headers: auth
      names = json["data"].map { |b| b["firstname"] }
      expect(names).to include("Bob")
      expect(names).not_to include("Alice")
    end

    it "excludes soft-deleted bookings" do
      pending_booking.soft_delete!(validate: false)
      get "/api/v1/bookings", headers: auth
      names = json["data"].map { |b| b["firstname"] }
      expect(names).not_to include("Bob")
    end

    it "exposes money as cents plus a formatted string" do
      get "/api/v1/bookings", params: { status: "confirmed" }, headers: auth
      price = json["data"].first["price"]
      expect(price["cents"]).to eq(40_000)
      expect(price["formatted"]).to be_present
    end
  end

  describe "GET /api/v1/bookings/:id" do
    let!(:lodging) { Lodging.create!(name: "Le Grand-Duc", price_night_cents: 12_000) }
    let!(:room) { Room.create!(name: "Chambre 1", level: 1) }
    let!(:booking) do
      Booking.create!(firstname: "Carla", from_date: Date.new(2026, 7, 1), to_date: Date.new(2026, 7, 2),
                      adults: 2, status: "confirmed", lodging: lodging)
    end
    let!(:reservation) { Reservation.create!(booking: booking, room: room, date: Date.new(2026, 7, 1)) }

    it "includes the day-by-day reservations" do
      get "/api/v1/bookings/#{booking.id}", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"]["reservations"].first["room"]["name"]).to eq("Chambre 1")
    end

    it "returns 404 for an unknown id" do
      get "/api/v1/bookings/0", headers: auth
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/availability" do
    let!(:lodging) { Lodging.create!(name: "Tiny house", price_night_cents: 8_000) }

    it "requires from and to" do
      get "/api/v1/availability", headers: auth
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects an inverted range" do
      get "/api/v1/availability", params: { from: "2026-07-10", to: "2026-07-01" }, headers: auth
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "marks days with an unavailability as unavailable" do
      Unavailability.create!(lodging: lodging, date: Date.new(2026, 7, 2))
      get "/api/v1/availability",
          params: { from: "2026-07-01", to: "2026-07-03", lodging_id: lodging.id }, headers: auth
      expect(response).to have_http_status(:ok)
      dates = json["lodgings"].first["dates"].index_by { |d| d["date"] }
      expect(dates["2026-07-01"]["available"]).to be(true)
      expect(dates["2026-07-02"]["available"]).to be(false)
      expect(json).not_to have_key("spaces")
    end
  end

  describe "GET /api/v1/payments" do
    let!(:booking) do
      Booking.create!(firstname: "Dora", from_date: Date.new(2026, 7, 1), to_date: Date.new(2026, 7, 2),
                      adults: 1, status: "confirmed")
    end
    # Phase 4 : tout Payment porte désormais un stay (verrouillage stay_id).
    let!(:stay) do
      Stay.create!(customer: Customer.create!(email: "dora@example.com", customer_type: "individual"),
                   source: "reservation", status: "confirmed", total_amount_cents: 5_000)
    end
    let!(:payment) do
      Payment.create!(booking: booking, stay: stay, amount_cents: 5_000, payment_method: "card",
                      status: "paid", stripe_payment_intent_id: "pi_secret_value")
    end

    it "never exposes raw Stripe identifiers" do
      get "/api/v1/payments/#{payment.id}", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"]).not_to have_key("stripe_payment_intent_id")
      expect(json["data"]).not_to have_key("stripe_checkout_session_id")
      expect(response.body).not_to include("pi_secret_value")
    end
  end

  describe "GET /api/v1/lodgings" do
    let!(:lodging) { Lodging.create!(name: "La Chevêche", price_night_cents: 9_000) }

    it "lists lodgings" do
      get "/api/v1/lodgings", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |l| l["name"] }).to include("La Chevêche")
    end
  end
end
