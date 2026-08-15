require "rails_helper"

# Issue #196 — le référentiel comptable réel entre par l'API.
#
# Ce qui est testé ici : l'idempotence sur le code (une reprise de 146 comptes
# se joue en plusieurs passes), la déduction classe/nature depuis le numéro (le
# PCMN la porte déjà, personne ne va la ressaisir 146 fois), et l'équilibre de
# l'à-nouveau — le seul contrôle dont dépend tout le reste de l'exercice.
RSpec.describe "API v1 — référentiel comptable", type: :request do
  let(:token) { "jeton-de-test" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  before { ENV["AGENT_API_TOKEN"] = token }
  after { ENV.delete("AGENT_API_TOKEN") }

  def body = JSON.parse(response.body)

  let!(:entity) { LegalEntity.create!(name: "Fondation Les 4 Sources", form: "foundation", vat_regime: "exempt") }

  describe "POST /api/v1/general_accounts" do
    it "crée un compte et déduit sa classe et sa nature du numéro" do
      post "/api/v1/general_accounts",
           params: { general_account: { code: "613313", name: "Rémunérations Pôle Technique" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "klass")).to eq(6)
      expect(body.dig("data", "nature")).to eq("expense")
    end

    it "respecte une nature explicite plutôt que la déduction" do
      post "/api/v1/general_accounts",
           params: { general_account: { code: "440000", name: "Fournisseurs", nature: "liability" } }.to_json,
           headers: headers

      expect(body.dig("data", "nature")).to eq("liability")
    end

    # Deux comptes 613313 et plus aucune balance n'est interprétable.
    it "retrouve le compte existant sur son code au lieu d'en créer un second" do
      post "/api/v1/general_accounts",
           params: { general_account: { code: "701001", name: "Bar" } }.to_json, headers: headers

      expect {
        post "/api/v1/general_accounts",
             params: { general_account: { code: "701001", name: "Bar et cellier" } }.to_json, headers: headers
      }.not_to change(GeneralAccount, :count)

      expect(response).to have_http_status(:ok)
      expect(GeneralAccount.find_by(code: "701001").name).to eq("Bar et cellier")
    end

    it "refuse un code non numérique" do
      post "/api/v1/general_accounts",
           params: { general_account: { code: "BAR", name: "Bar" } }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "s'adresse par le code en lecture" do
      GeneralAccount.create!(code: "570000", name: "Caisse", klass: 5, nature: "asset")

      get "/api/v1/general_accounts/570000", headers: headers

      expect(body.dig("data", "name")).to eq("Caisse")
    end
  end

  describe "POST /api/v1/analytic_accounts" do
    it "crée un axe et le rattache à une équipe" do
      team = Team.create!(name: "Pôle Technique")

      post "/api/v1/analytic_accounts",
           params: { analytic_account: { code: "TECH", name: "Pôle Technique", team_id: team.id } }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "team_name")).to eq("Pôle Technique")
    end

    # Winbooks connaît une quinzaine de pôles, claudy six. On laisse le lien
    # vide plutôt que d'inventer une équipe que personne n'a décidée.
    it "accepte un axe sans équipe" do
      post "/api/v1/analytic_accounts",
           params: { analytic_account: { code: "GOUV", name: "Pôle Gouvernance" } }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "team_id")).to be_nil
    end

    it "est idempotent sur le code" do
      params = { analytic_account: { code: "GOUV", name: "Pôle Gouvernance" } }
      post "/api/v1/analytic_accounts", params: params.to_json, headers: headers

      expect {
        post "/api/v1/analytic_accounts", params: params.to_json, headers: headers
      }.not_to change(AnalyticAccount, :count)
    end
  end

  describe "POST /api/v1/fiscal_years" do
    it "crée un exercice" do
      post "/api/v1/fiscal_years", params: {
        fiscal_year: { legal_entity_id: entity.id, starts_on: "2024-01-01", ends_on: "2024-12-31" }
      }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "label")).to eq("2024")
    end

    it "retrouve l'exercice existant sur (entité, date de début)" do
      params = { fiscal_year: { legal_entity_id: entity.id, starts_on: "2024-01-01", ends_on: "2024-12-31" } }
      post "/api/v1/fiscal_years", params: params.to_json, headers: headers

      expect {
        post "/api/v1/fiscal_years", params: params.to_json, headers: headers
      }.not_to change(FiscalYear, :count)

      expect(response).to have_http_status(:ok)
    end

    # Rouvrir un exercice clos est une décision comptable, pas un effet de bord
    # d'un import rejoué.
    it "refuse de toucher un exercice clôturé" do
      year = FiscalYear.create!(legal_entity: entity, starts_on: Date.new(2023, 1, 1),
                                ends_on: Date.new(2023, 12, 31), status: "closed")

      patch "/api/v1/fiscal_years/#{year.id}",
            params: { fiscal_year: { status: "open" } }.to_json, headers: headers

      expect(response).to have_http_status(:conflict)
      expect(year.reload.status).to eq("closed")
    end
  end

  describe "POST /api/v1/opening_entries" do
    let!(:year) do
      FiscalYear.create!(legal_entity: entity, starts_on: Date.new(2024, 1, 1), ends_on: Date.new(2024, 12, 31))
    end
    let!(:banque) { GeneralAccount.create!(code: "550000", name: "Comptes courants", klass: 5, nature: "asset") }
    let!(:fonds) { GeneralAccount.create!(code: "100000", name: "Fonds de la fondation", klass: 1, nature: "equity") }

    def poste(lines, extra = {})
      post "/api/v1/opening_entries",
           params: { fiscal_year_id: year.id, lines: lines }.merge(extra).to_json, headers: headers
    end

    it "pose l'à-nouveau, daté du premier jour de l'exercice" do
      poste([{ general_account_code: "550000", debit_cents: 235_667 },
             { general_account_code: "100000", credit_cents: 235_667 }])

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "journal")).to eq("opening")
      expect(body.dig("data", "entry_date")).to eq("2024-01-01")
      expect(body.dig("data", "debit_cents")).to eq(235_667)
      expect(body.dig("data", "lines").size).to eq(2)
    end

    # Le contrôle dont tout dépend : une ouverture qui ne balance pas contamine
    # l'exercice entier.
    it "refuse un à-nouveau déséquilibré, et dit de combien" do
      expect {
        poste([{ general_account_code: "550000", debit_cents: 235_667 },
               { general_account_code: "100000", credit_cents: 200_000 }])
      }.not_to change(JournalEntry, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["imbalance_cents"]).to eq(35_667)
      expect(body["message"]).to match(/déséquilibré/)
    end

    # Un à-nouveau amputé d'une ligne balancerait quand même après suppression
    # d'un couple : il faut donc s'arrêter, pas continuer sans.
    it "s'arrête sur un compte inconnu au lieu de poser une ouverture amputée" do
      expect {
        poste([{ general_account_code: "550000", debit_cents: 100 },
               { general_account_code: "999999", credit_cents: 100 }])
      }.not_to change(JournalEntry, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["message"]).to match(/999999/)
    end

    # Une ligne qui perd son axe en silence rend la balance analytique fausse
    # sans que rien ne le signale.
    it "refuse un axe analytique inconnu plutôt que de l'ignorer" do
      expect {
        poste([{ general_account_code: "550000", debit_cents: 100, analytic_account_code: "NEXISTEPAS" },
               { general_account_code: "100000", credit_cents: 100 }])
      }.not_to change(JournalEntry, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["message"]).to match(/NEXISTEPAS/)
    end

    it "porte l'axe analytique quand il existe" do
      axe = AnalyticAccount.create!(code: "TECH", name: "Pôle Technique")

      poste([{ general_account_code: "550000", debit_cents: 100, analytic_account_code: "TECH" },
             { general_account_code: "100000", credit_cents: 100 }])

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "lines", 0, "analytic_account_code")).to eq(axe.code)
    end

    it "contre-passe l'ouverture précédente au lieu d'en empiler une seconde" do
      poste([{ general_account_code: "550000", debit_cents: 100_000 },
             { general_account_code: "100000", credit_cents: 100_000 }])
      première = JournalEntry.find(body.dig("data", "id"))

      poste([{ general_account_code: "550000", debit_cents: 120_000 },
             { general_account_code: "100000", credit_cents: 120_000 }])

      expect(response).to have_http_status(:created)
      expect(JournalEntry.exists?(reversal_of_id: première.id)).to be(true)

      # Trois écritures — l'originale, sa contre-passation, la nouvelle — dont le
      # net vaut la dernière posée. C'est ça, corriger sans mentir.
      lignes = JournalLine.joins(:journal_entry).where(journal_entries: { fiscal_year_id: year.id })
      expect(lignes.sum(:debit_cents) - lignes.sum(:credit_cents)).to eq(0)
      expect(JournalEntry.where(fiscal_year_id: year.id, journal: "opening").count).to eq(3)
      net = lignes.where(general_account_id: banque.id).sum(:debit_cents) -
            lignes.where(general_account_id: banque.id).sum(:credit_cents)
      expect(net).to eq(120_000)
    end

    # Le troisième dépôt est celui qui casse une contre-passation naïve : elle
    # retomberait sur la toute première écriture, déjà annulée.
    it "supporte un troisième dépôt sans retomber sur une écriture déjà annulée" do
      3.times do |i|
        poste([{ general_account_code: "550000", debit_cents: 100_000 + i },
               { general_account_code: "100000", credit_cents: 100_000 + i }])
        expect(response).to have_http_status(:created)
      end

      lignes = JournalLine.joins(:journal_entry).where(journal_entries: { fiscal_year_id: year.id })
      net = lignes.where(general_account_id: banque.id).sum(:debit_cents) -
            lignes.where(general_account_id: banque.id).sum(:credit_cents)
      expect(net).to eq(100_002)
    end

    it "refuse un exercice clôturé" do
      year.update!(status: "closed")

      poste([{ general_account_code: "550000", debit_cents: 100 },
             { general_account_code: "100000", credit_cents: 100 }])

      expect(response).to have_http_status(:conflict)
    end

    it "refuse sans jeton" do
      post "/api/v1/opening_entries", params: { fiscal_year_id: year.id, lines: [] }.to_json,
                                      headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/" do
    it "annonce les nouvelles ressources" do
      get "/api/v1/", headers: headers

      expect(body["resources"].map { |r| r["name"] })
        .to include("general_accounts", "analytic_accounts", "fiscal_years", "opening_entries")
    end
  end
end
