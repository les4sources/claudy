require "rails_helper"

RSpec.describe "Api::V1::HumanRoles", type: :request do
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

  let!(:michael) { Human.create!(name: "Michael", email: "michael@example.com") }
  let!(:other) { Human.create!(name: "Autre", email: "autre@example.com") }
  let!(:watch_role) { Role.create!(name: "Veilleur·euse") }
  let!(:misc_role) { Role.create!(name: "Cuisine") }

  let!(:michael_mon) do
    HumanRole.create!(human: michael, role: watch_role, date: Date.new(2026, 6, 15), status: :selected)
  end
  let!(:michael_thu) do
    HumanRole.create!(human: michael, role: watch_role, date: Date.new(2026, 6, 18), status: :backup)
  end
  let!(:other_tue) do
    HumanRole.create!(human: other, role: watch_role, date: Date.new(2026, 6, 16), status: :selected)
  end
  let!(:michael_kitchen) do
    HumanRole.create!(human: michael, role: misc_role, date: Date.new(2026, 6, 17), status: :selected)
  end

  describe "GET /api/v1/human_roles" do
    it "lists roles with pagination meta, ordered by date" do
      get "/api/v1/human_roles", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"]).to be_an(Array)
      expect(json["meta"]).to include("page", "per_page", "total")
      dates = json["data"].map { |r| r["date"] }
      expect(dates).to eq(dates.sort)
    end

    it "filters by human_id" do
      get "/api/v1/human_roles", params: { human_id: michael.id }, headers: auth
      human_ids = json["data"].map { |r| r["human"]["id"] }
      expect(human_ids).to all(eq(michael.id))
    end

    it "filters by role_id and status to isolate confirmed watch shifts" do
      get "/api/v1/human_roles",
          params: { human_id: michael.id, role_id: watch_role.id, status: "selected" }, headers: auth
      expect(json["data"].length).to eq(1)
      shift = json["data"].first
      expect(shift["date"]).to eq("2026-06-15")
      expect(shift["status"]).to eq("selected")
      expect(shift["role"]["name"]).to eq("Veilleur·euse")
    end

    it "filters by date range with from/to" do
      get "/api/v1/human_roles",
          params: { from: "2026-06-16", to: "2026-06-17" }, headers: auth
      dates = json["data"].map { |r| r["date"] }
      expect(dates).to match_array(%w[2026-06-16 2026-06-17])
    end

    it "exposes status, role and has_watchman_note in the payload" do
      get "/api/v1/human_roles", params: { human_id: michael.id, role_id: watch_role.id }, headers: auth
      record = json["data"].first
      expect(record).to include("date", "status", "role", "has_watchman_note")
      expect(record["type"]).to eq("human_role")
    end

    it "requires authentication" do
      get "/api/v1/human_roles"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/human_roles/:id" do
    it "returns a single dated role" do
      get "/api/v1/human_roles/#{michael_mon.id}", headers: auth
      expect(response).to have_http_status(:ok)
      expect(json["data"]["id"]).to eq(michael_mon.id)
      expect(json["data"]["date"]).to eq("2026-06-15")
    end
  end
end
