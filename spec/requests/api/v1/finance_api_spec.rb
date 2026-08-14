require "rails_helper"

# Le catalogue interne et les fiches papier sont les seules ressources de l'API
# où POST existe. Ce spec vérifie surtout ce qui protège un agent qui rejoue son
# import : l'upsert, le refus d'écraser un palier de prix, et l'idempotence de
# l'encodage.
RSpec.describe "Api::V1 bar & comptes internes", type: :request do
  let(:token) { "test-token-123" }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }
  let(:headers) { auth.merge("CONTENT_TYPE" => "application/json") }

  around do |example|
    previous = ENV["AGENT_API_TOKEN"]
    ENV["AGENT_API_TOKEN"] = token
    example.run
    ENV["AGENT_API_TOKEN"] = previous
  end

  def json = JSON.parse(response.body)

  def post_json(path, payload)
    post path, params: payload.to_json, headers: headers
  end

  def patch_json(path, payload)
    patch path, params: payload.to_json, headers: headers
  end

  describe "POST /api/v1/catalog_items" do
    let(:payload) do
      { catalog_item: { name: "Taras Boulba", channel: "bar", category: "Bières", unit: "piece" } }
    end

    it "crée l'article et le signale dans meta" do
      expect { post_json "/api/v1/catalog_items", payload }.to change(CatalogItem, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("name" => "Taras Boulba", "channel" => "bar", "channel_label" => "Bar")
      expect(json["meta"]["created"]).to be(true)
    end

    it "reposté, met à jour au lieu de dupliquer" do
      post_json "/api/v1/catalog_items", payload
      expect do
        post_json "/api/v1/catalog_items", payload.deep_merge(catalog_item: { category: "Bières belges" })
      end.not_to change(CatalogItem, :count)

      expect(response).to have_http_status(:ok)
      expect(json["meta"]["created"]).to be(false)
      expect(json["data"]["category"]).to eq("Bières belges")
    end

    it "refuse un canal inconnu" do
      post_json "/api/v1/catalog_items", { catalog_item: { name: "X", channel: "terrasse" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["messages"].join).to match(/canal|channel/i)
    end

    it "exige un jeton" do
      post "/api/v1/catalog_items", params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "paliers de prix" do
    let!(:item) { CatalogItem.create!(name: "Bionina", channel: "bar", category: "Softs") }

    it "pose un palier et l'expose formaté" do
      post_json "/api/v1/catalog_items/#{item.id}/prices",
                { price: { active_from: "2026-07-01", member_price_cents: 165,
                           purchase_price_cents: 150, public_price_cents: 300 } }

      expect(response).to have_http_status(:created)
      expect(json["data"]["member_price"]["cents"]).to eq(165)
      expect(json["data"]["purchase_price"]["cents"]).to eq(150)
      expect(json["data"]["open_ended"]).to be(true)
    end

    it "refuse d'écraser un palier qui couvre déjà la période" do
      item.catalog_prices.create!(active_from: Date.new(2026, 1, 1), member_price_cents: 150)

      expect do
        post_json "/api/v1/catalog_items/#{item.id}/prices",
                  { price: { active_from: "2026-07-01", member_price_cents: 165 } }
      end.not_to change(CatalogPrice, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["messages"].join).to match(/chevauche/i)
    end

    it "laisse corriger un palier existant en PATCH" do
      price = item.catalog_prices.create!(active_from: Date.new(2026, 7, 1), member_price_cents: 165)

      patch_json "/api/v1/catalog_items/#{item.id}/prices/#{price.id}", { price: { public_price_cents: 300 } }

      expect(response).to have_http_status(:ok)
      expect(price.reload.public_price_cents).to eq(300)
      expect(price.member_price_cents).to eq(165)
    end
  end

  describe "GET /api/v1/catalog_items" do
    let!(:item) { CatalogItem.create!(name: "Moinette", channel: "bar", category: "Bières") }

    before do
      item.catalog_prices.create!(active_from: Date.new(2023, 1, 1), active_until: Date.new(2026, 6, 30),
                                  member_price_cents: 190)
      item.catalog_prices.create!(active_from: Date.new(2026, 7, 1), member_price_cents: 210)
      CatalogItem.create!(name: "Avoine bio", channel: "grocery", category: "Vracs secs")
    end

    it "filtre par canal et par nom" do
      get "/api/v1/catalog_items", params: { channel: "bar", q: "moin" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |i| i["name"] }).to eq(["Moinette"])
      expect(json["meta"]).to include("page", "total")
    end

    it "résout le prix à la date demandée, pas à celle du jour" do
      get "/api/v1/catalog_items", params: { q: "Moinette", on: "2026-05-15" }, headers: auth
      expect(json["data"].first["price"]["member_price"]["cents"]).to eq(190)

      get "/api/v1/catalog_items", params: { q: "Moinette", on: "2026-07-31" }, headers: auth
      expect(json["data"].first["price"]["member_price"]["cents"]).to eq(210)
    end

    it "signale une date illisible plutôt que de planter" do
      get "/api/v1/catalog_items", params: { on: "juillet" }, headers: auth
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/member_accounts" do
    let!(:household) { Household.create!(name: "de Bruyère", kind: "resident") }
    let!(:account) { MemberAccount.create!(name: "Ménage de Bruyère", kind: "household", household: household) }

    before do
      MemberAccount.create!(name: "Ménage Charlie", kind: "entity")
      account.account_entries.create!(entry_date: Date.new(2026, 7, 31), amount_cents: 1_650, flow: "bar")
    end

    it "retrouve un compte par fragment de nom, avec son solde" do
      get "/api/v1/member_accounts", params: { q: "Bruyère" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(1)
      expect(json["data"].first).to include("name" => "Ménage de Bruyère", "balance_cents" => 1_650,
                                            "entries_count" => 1, "kind_label" => "Ménage")
    end

    it "n'expose ni création ni édition — un compte s'ouvre dans l'app" do
      expect { post_json "/api/v1/member_accounts", { member_account: { name: "X", kind: "entity" } } }
        .to raise_error(ActionController::RoutingError)
      expect { patch_json "/api/v1/member_accounts/#{account.id}", { member_account: { name: "Y" } } }
        .to raise_error(ActionController::RoutingError)
    end
  end

  describe "fiches papier" do
    let!(:account_a) { MemberAccount.create!(name: "Ménage Alpha", kind: "entity") }
    let!(:account_b) { MemberAccount.create!(name: "Ménage Bravo", kind: "entity") }
    let!(:biere) { CatalogItem.create!(name: "Moinette", channel: "bar", category: "Bières") }
    let!(:chips) { CatalogItem.create!(name: "Chips ReBel", channel: "bar", category: "Snacks") }

    before do
      biere.catalog_prices.create!(active_from: Date.new(2026, 7, 1), member_price_cents: 210)
      chips.catalog_prices.create!(active_from: Date.new(2026, 7, 1), member_price_cents: 281)
    end

    def create_sheet
      post_json "/api/v1/paper_sheets",
                { paper_sheet: { period_month: "2026-07-01", channel: "bar", entry_mode: "quantity" } }
      json["data"]["id"]
    end

    it "crée la fiche, ramène le mois au 1er et date les écritures du dernier jour" do
      post_json "/api/v1/paper_sheets",
                { paper_sheet: { period_month: "2026-07-18", channel: "bar", entry_mode: "quantity" } }

      expect(response).to have_http_status(:created)
      expect(json["data"]["period_month"]).to eq("2026-07-01")
      expect(json["data"]["entry_date"]).to eq("2026-07-31")
      expect(json["meta"]["created"]).to be(true)
    end

    it "repostée, retrouve la fiche du mois au lieu d'en créer une seconde" do
      create_sheet
      expect { create_sheet }.not_to change(PaperSheet, :count)
      expect(json["meta"]["created"]).to be(false)
    end

    it "encode la matrice, écrit les écritures et rend les totaux par compte" do
      sheet_id = create_sheet

      post_json "/api/v1/paper_sheets/#{sheet_id}/encode",
                { entry_mode: "quantity",
                  cells: { account_a.id.to_s => { biere.id.to_s => 2, chips.id.to_s => 7 },
                           account_b.id.to_s => { biere.id.to_s => 4 } } }

      expect(response).to have_http_status(:ok)
      expect(json["meta"]["encoding"]).to include("created" => 3, "updated" => 0, "deleted" => 0)
      expect(json["data"]["status"]).to eq("encoded")

      # 2 × 2,10 + 7 × 2,81 = 23,87 €  ·  4 × 2,10 = 8,40 €
      totaux = json["data"]["totals_by_account"].to_h { |line| [line["name"], line["cents"]] }
      expect(totaux).to eq("Ménage Alpha" => 2_387, "Ménage Bravo" => 840)
      expect(json["data"]["total_cents"]).to eq(3_227)

      expect(account_a.reload.balance_cents).to eq(2_387)
      entry = AccountEntry.find_by(member_account: account_b, catalog_item_id: biere.id)
      expect(entry.quantity).to eq(4)
      expect(entry.unit_price_cents).to eq(210)
      expect(entry.entry_date).to eq(Date.new(2026, 7, 31))
    end

    it "rejoué, met à jour sans dupliquer" do
      sheet_id = create_sheet
      cells = { account_a.id.to_s => { biere.id.to_s => 2 } }
      post_json "/api/v1/paper_sheets/#{sheet_id}/encode", { cells: cells }

      expect do
        post_json "/api/v1/paper_sheets/#{sheet_id}/encode", { cells: cells }
      end.not_to change(AccountEntry, :count)

      expect(json["meta"]["encoding"]).to include("created" => 0, "updated" => 1)
    end

    it "une cellule remise à zéro supprime son écriture" do
      sheet_id = create_sheet
      post_json "/api/v1/paper_sheets/#{sheet_id}/encode",
                { cells: { account_a.id.to_s => { biere.id.to_s => 2 } } }

      post_json "/api/v1/paper_sheets/#{sheet_id}/encode",
                { cells: { account_a.id.to_s => { biere.id.to_s => 0 } } }

      expect(json["meta"]["encoding"]).to include("deleted" => 1)
      expect(account_a.reload.balance_cents).to eq(0)
    end

    it "ne touche pas à une écriture verrouillée par un décompte émis" do
      sheet_id = create_sheet
      post_json "/api/v1/paper_sheets/#{sheet_id}/encode",
                { cells: { account_a.id.to_s => { biere.id.to_s => 2 } } }
      AccountEntry.last.update_column(:locked_at, Time.current)

      post_json "/api/v1/paper_sheets/#{sheet_id}/encode",
                { cells: { account_a.id.to_s => { biere.id.to_s => 9 } } }

      expect(response).to have_http_status(:ok)
      expect(json["meta"]["encoding"]["locked"]).to eq(1)
      expect(AccountEntry.last.amount_cents).to eq(420)
    end

    it "exige des cellules" do
      sheet_id = create_sheet
      post_json "/api/v1/paper_sheets/#{sheet_id}/encode", { entry_mode: "quantity" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "découverte" do
    it "annonce les nouvelles ressources et la règle d'upsert" do
      get "/api/v1", headers: auth

      noms = json["resources"].map { |r| r["name"] }
      expect(noms).to include("catalog_items", "member_accounts", "paper_sheets")
      expect(json["conventions"]["upsert"]).to match(/UPSERT/)
    end

    it "documente les nouveaux chemins dans la spec OpenAPI" do
      get "/api/v1/openapi", headers: auth

      expect(json["paths"]).to include("/catalog_items", "/member_accounts", "/paper_sheets",
                                       "/paper_sheets/{id}/encode")
      expect(json["components"]["schemas"]).to include("CatalogItem", "CatalogPrice",
                                                       "MemberAccount", "PaperSheet")
    end
  end
end
