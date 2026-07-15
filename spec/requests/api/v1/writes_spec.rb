require "rails_helper"

# Covers the write surface added to the agent API: PATCH (update) and DELETE
# (soft-delete). All resource controllers share the same BaseController helpers
# and pattern, so a representative set proves the mechanism for all of them.
RSpec.describe "Api::V1 writes", type: :request do
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

  describe "PATCH /api/v1/bookings/:id" do
    let!(:booking) do
      Booking.create!(firstname: "Alice", from_date: Date.new(2026, 7, 1),
                      to_date: Date.new(2026, 7, 5), adults: 2, status: "pending")
    end

    # NOTE: a benign field is used on purpose. Editing `status` triggers the
    # model's notify_on_status_change callback (customer emails) — see the
    # writes_spec README note; that side-effect is intentional, not tested here.
    it "updates an editable field from a wrapped body and returns the record" do
      patch "/api/v1/bookings/#{booking.id}",
            params: { booking: { group_name: "Famille Test" } }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(json["data"]).to be_present
      expect(booking.reload.group_name).to eq("Famille Test")
    end

    it "requires authentication" do
      patch "/api/v1/bookings/#{booking.id}", params: { booking: { group_name: "x" } }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "404s for an unknown id" do
      patch "/api/v1/bookings/0", params: { booking: { group_name: "x" } }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/bookings/:id (soft-delete)" do
    let!(:booking) do
      Booking.create!(firstname: "Bob", from_date: Date.new(2026, 8, 1),
                      to_date: Date.new(2026, 8, 3), adults: 1, status: "pending")
    end

    it "soft-deletes and the record then 404s but stays in the table" do
      delete "/api/v1/bookings/#{booking.id}", headers: auth
      expect(response).to have_http_status(:no_content)

      get "/api/v1/bookings/#{booking.id}", headers: auth
      expect(response).to have_http_status(:not_found)

      # Row is not destroyed — only flagged deleted (auditable). `with_deleted`
      # from the soft_deletion gem lifts the default scope inside its block.
      Booking.with_deleted do
        record = Booking.find(booking.id)
        expect(record.deleted_at).to be_present
      end
    end
  end

  describe "validation errors" do
    let!(:cycle) { Cycle.create!(name: "Cycle 1", start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 3, 1)) }

    it "returns 422 with messages when the update is invalid" do
      patch "/api/v1/cycles/#{cycle.id}", params: { cycle: { name: "" } }, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("unprocessable_entity")
      expect(json["messages"]).to be_an(Array).and be_present
      expect(cycle.reload.name).to eq("Cycle 1")
    end
  end

  describe "Stripe identifiers stay provider-managed" do
    let!(:booking) do
      Booking.create!(firstname: "Carla", from_date: Date.new(2026, 7, 1),
                      to_date: Date.new(2026, 7, 2), adults: 1, status: "confirmed")
    end
    # Phase 4 : tout Payment porte désormais un stay (verrouillage stay_id).
    let!(:stay) do
      Stay.create!(customer: Customer.create!(email: "carla@example.com", customer_type: "individual"),
                   source: "reservation", status: "confirmed", total_amount_cents: 5_000)
    end
    let!(:payment) do
      Payment.create!(booking: booking, stay: stay, amount_cents: 5_000, payment_method: "card",
                      status: "pending", stripe_payment_intent_id: "pi_original")
    end

    it "edits status but never the Stripe id" do
      patch "/api/v1/payments/#{payment.id}",
            params: { payment: { status: "paid", stripe_payment_intent_id: "pi_hacked" } },
            headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(payment.reload.status).to eq("paid")
      expect(payment.stripe_payment_intent_id).to eq("pi_original")
    end
  end

  describe "customers and stays are writable too" do
    let!(:customer) do
      Customer.create!(email: "edit@example.com", first_name: "Edith", customer_type: "individual")
    end

    it "edits a customer" do
      patch "/api/v1/customers/#{customer.id}",
            params: { customer: { first_name: "Édith", phone: "+32470000000" } }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(customer.reload.first_name).to eq("Édith")
    end

    it "soft-deletes a customer" do
      delete "/api/v1/customers/#{customer.id}", headers: auth
      expect(response).to have_http_status(:no_content)
      get "/api/v1/customers/#{customer.id}", headers: auth
      expect(response).to have_http_status(:not_found)
    end

    it "never lets the API write the Stripe customer id" do
      customer.update_column(:stripe_customer_id, "cus_original")
      patch "/api/v1/customers/#{customer.id}",
            params: { customer: { stripe_customer_id: "cus_hacked", phone: "+32470111222" } },
            headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      expect(customer.reload.stripe_customer_id).to eq("cus_original")
    end
  end

  describe "the OpenAPI spec and discovery index advertise the write surface" do
    it "documents PATCH/DELETE for customers and stays" do
      get "/api/v1/openapi", headers: auth
      expect(json.dig("paths", "/customers/{id}", "patch")).to be_present
      expect(json.dig("paths", "/stays/{id}", "delete")).to be_present
      expect(json.dig("paths", "/bookings/{id}", "patch")).to be_present
    end

    it "lists customers and stays in the discovery index" do
      get "/api/v1", headers: auth
      expect(json["resources"].map { |r| r["name"] }).to include("customers", "stays")
      expect(json["conventions"]).to have_key("writes")
    end
  end

  describe "create is still not exposed" do
    it "has no POST route for a resource" do
      expect { post "/api/v1/bookings", headers: auth }.to raise_error(ActionController::RoutingError)
    end
  end
end
