require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Issue #198 — déposer un CODA et créer le compte de trésorerie qui le reçoit,
# par l'API. Le point le plus important est le comportement du RE-dépôt : une
# reprise se joue en plusieurs passes, et rejouer un fichier déjà déposé doit
# être une opération normale, pas une erreur.
RSpec.describe "API v1 — trésorerie et CODA", type: :request do
  include FinanceBuilders

  let(:token) { "jeton-de-test" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  before { ENV["AGENT_API_TOKEN"] = token }
  after { ENV.delete("AGENT_API_TOKEN") }

  def body = JSON.parse(response.body)

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:compte_general) { build_general_account(code: "550000", name: "Comptes courants") }

  def fixture(name) = Rails.root.join("spec/fixtures/coda/#{name}.cod").read

  describe "POST /api/v1/cash_accounts" do
    it "crée un compte de trésorerie et le relie à son compte général par le code" do
      post "/api/v1/cash_accounts", params: {
        cash_account: { name: "Fondation — Triodos", kind: "bank", iban: "BE55 0680 0000 0000",
                        legal_entity_id: entity.id, general_account_code: "550000" }
      }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "general_account_code")).to eq("550000")
      expect(CashAccount.last.general_account).to eq(compte_general)
    end

    it "retrouve le compte existant sur son nom" do
      params = { cash_account: { name: "Fondation — Triodos", kind: "bank",
                                 legal_entity_id: entity.id, general_account_code: "550000" } }
      post "/api/v1/cash_accounts", params: params.to_json, headers: headers

      expect {
        post "/api/v1/cash_accounts", params: params.to_json, headers: headers
      }.not_to change(CashAccount, :count)

      expect(response).to have_http_status(:ok)
    end

    it "refuse un compte général inconnu plutôt que de créer un compte sans contrepartie" do
      post "/api/v1/cash_accounts", params: {
        cash_account: { name: "Compte fantôme", kind: "bank",
                        legal_entity_id: entity.id, general_account_code: "999999" }
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(CashAccount.count).to eq(0)
    end
  end

  describe "POST /api/v1/coda_imports" do
    let!(:compte) do
      CashAccount.create!(name: "Triodos", kind: "bank", legal_entity: entity,
                          general_account: compte_general, iban: "BE55068000000000")
    end

    it "dépose le fichier et rend le rapport d'import" do
      expect {
        post "/api/v1/coda_imports",
             params: { filename: "nominal.cod", content: fixture("nominal") }.to_json, headers: headers
      }.to change(CashEntry, :count).by(2)

      expect(response).to have_http_status(:created)
      expect(body.dig("meta", "status")).to eq("imported")
      expect(body.dig("meta", "entries_created")).to eq(2)
      expect(body.dig("data", "statements", 0, "new_balance_cents")).to eq(185_000)
    end

    # Rejouer un import est une opération normale — c'est ce qui rend une
    # reprise en plusieurs passes possible.
    it "rend 200 sans rien créer quand le fichier a déjà été déposé" do
      post "/api/v1/coda_imports",
           params: { filename: "nominal.cod", content: fixture("nominal") }.to_json, headers: headers

      expect {
        post "/api/v1/coda_imports",
             params: { filename: "nominal.cod", content: fixture("nominal") }.to_json, headers: headers
      }.not_to change(CashEntry, :count)

      expect(response).to have_http_status(:ok)
      expect(body.dig("meta", "status")).to eq("already_imported")
    end

    # Le motif porte le relevé ET l'écart chiffré : c'est ce qui permet à la
    # compta de savoir quoi demander à la banque.
    it "rend 422 avec le motif chiffré quand un relevé ne se referme pas" do
      expect {
        post "/api/v1/coda_imports",
             params: { filename: "ecart.cod", content: fixture("ecart_intra") }.to_json, headers: headers
      }.not_to change(CashEntry, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["message"]).to match(/Écart de/)
    end

    it "refuse un contenu vide" do
      post "/api/v1/coda_imports", params: { filename: "vide.cod", content: "" }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuse sans jeton" do
      post "/api/v1/coda_imports", params: { content: fixture("nominal") }.to_json,
                                   headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rend le détail d'un import avec ses relevés" do
      post "/api/v1/coda_imports",
           params: { filename: "nominal.cod", content: fixture("nominal") }.to_json, headers: headers
      id = body.dig("data", "id")

      get "/api/v1/coda_imports/#{id}", headers: headers

      expect(body.dig("data", "statements", 0, "cash_account_name")).to eq("Triodos")
      expect(body.dig("data", "entries_count")).to eq(2)
    end
  end
end
