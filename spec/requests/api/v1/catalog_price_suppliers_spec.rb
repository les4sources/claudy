require "rails_helper"

# Le fournisseur d'un palier de prix passe aussi par l'API agent : c'est par là
# que les factures fournisseurs sont reprises dans le catalogue.
RSpec.describe "Api::V1 fournisseur des paliers de prix", type: :request do
  let(:token) { "test-token-fournisseur" }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }

  around do |example|
    previous = ENV["AGENT_API_TOKEN"]
    ENV["AGENT_API_TOKEN"] = token
    example.run
    ENV["AGENT_API_TOKEN"] = previous
  end

  def json = JSON.parse(response.body)

  let!(:item) { CatalogItem.create!(name: "Noix", channel: "grocery", category: "Fruits secs", unit: "kg") }
  let!(:agricovert) { ThirdParty.create!(name: "Agricovert", kind: "supplier", iban: "BE32780593687402") }
  let!(:client) { ThirdParty.create!(name: "Épicerie de la Gare", kind: "customer") }

  describe "POST /api/v1/catalog_items/:id/prices" do
    it "pose le fournisseur et le rend dans la réponse" do
      post "/api/v1/catalog_items/#{item.id}/prices", headers: auth, as: :json, params: {
        price: { active_from: "2026-09-30", purchase_price_cents: 2979, member_price_cents: 3485, third_party_id: agricovert.id }
      }

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "third_party")).to eq("id" => agricovert.id, "name" => "Agricovert")
    end

    it "rend third_party à null quand il n'y en a pas" do
      post "/api/v1/catalog_items/#{item.id}/prices", headers: auth, as: :json, params: {
        price: { active_from: "2026-09-30", member_price_cents: 3485 }
      }

      expect(json.dig("data", "third_party")).to be_nil
    end

    it "refuse un tiers client (422)" do
      post "/api/v1/catalog_items/#{item.id}/prices", headers: auth, as: :json, params: {
        price: { active_from: "2026-09-30", member_price_cents: 3485, third_party_id: client.id }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/third_parties" do
    it "filtre les fournisseurs par nom, sans jamais exposer l'IBAN" do
      get "/api/v1/third_parties", headers: auth, params: { kind: "supplier", q: "agri" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |t| t["name"] }).to eq(["Agricovert"])
      expect(response.body).not_to include("BE32780593687402")
      expect(json["data"].first.keys).not_to include("iban")
    end

    it "exclut les clients du filtre fournisseur" do
      get "/api/v1/third_parties", headers: auth, params: { kind: "supplier" }

      expect(json["data"].map { |t| t["name"] }).not_to include("Épicerie de la Gare")
    end

    it "exige le token" do
      get "/api/v1/third_parties"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
