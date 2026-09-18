require "rails_helper"

# Issue #339 — surface agent en lecture seule des Pizza Party rattachées.
RSpec.describe "API v1 — party_reservations", type: :request do
  around do |example|
    url, key, agent = ENV["TRANCHESDEVIE_API_URL"], ENV["TRANCHESDEVIE_API_KEY"], ENV["AGENT_API_TOKEN"]
    tdv_env!
    ENV["AGENT_API_TOKEN"] = "agent-test-token"
    example.run
    ENV["TRANCHESDEVIE_API_URL"] = url
    ENV["TRANCHESDEVIE_API_KEY"] = key
    ENV["AGENT_API_TOKEN"] = agent
  end

  let(:headers) { { "Authorization" => "Bearer agent-test-token" } }
  let(:customer) { Customer.create!(email: "api@example.com", customer_type: "organization", organization_name: "Scouts") }
  let(:stay) { Stay.create!(customer: customer, status: "confirmed") }

  before do
    stub_tdv_order(tdv_order(id: 1234))
    TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)
  end

  it "liste les parties rattachées" do
    get "/api/v1/party_reservations", headers: headers
    expect(response).to have_http_status(:ok)

    body = JSON.parse(response.body)
    party = body["data"].first
    expect(party["type"]).to eq("party_reservation")
    expect(party["external_id"]).to eq(1234)
    expect(party["status"]).to eq("active")
    expect(party["group_name"]).to eq("Scouts de Namur")
    expect(party["price"]["cents"]).to eq(27_000)
    expect(party["stay_id"]).to eq(stay.id)
  end

  it "filtre par séjour" do
    autre_stay = Stay.create!(customer: customer, status: "confirmed")
    get "/api/v1/party_reservations", params: { stay_id: autre_stay.id }, headers: headers
    expect(JSON.parse(response.body)["data"]).to be_empty
  end

  it "renvoie le détail d'une party" do
    reservation = stay.reload.party_reservations.first
    get "/api/v1/party_reservations/#{reservation.id}", headers: headers
    expect(JSON.parse(response.body).dig("data", "external_number")).to eq("TV-20261009-1234")
  end

  it "expose les parties du séjour dans GET /api/v1/stays/:id" do
    get "/api/v1/stays/#{stay.id}", headers: headers
    parties = JSON.parse(response.body).dig("data", "party_reservations")
    expect(parties.size).to eq(1)
    expect(parties.first["external_id"]).to eq(1234)
  end

  it "refuse sans jeton d'agent" do
    get "/api/v1/party_reservations"
    expect(response).to have_http_status(:unauthorized)
  end
end
