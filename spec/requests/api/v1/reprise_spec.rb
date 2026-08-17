require "rails_helper"

# Issue #193 — les trois écritures que la reprise de l'historique exige :
# créer un compte, poser une écriture, enregistrer un règlement. Ce qui est
# testé ici, c'est surtout l'IDEMPOTENCE : une reprise de quatre ans se joue
# forcément en plusieurs passes, et une passe qui duplique est pire qu'une passe
# qui échoue — elle est invisible.
RSpec.describe "API v1 — reprise de l'historique", type: :request do
  let(:token) { "jeton-de-test" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  before { ENV["AGENT_API_TOKEN"] = token }
  after { ENV.delete("AGENT_API_TOKEN") }

  def body = JSON.parse(response.body)

  describe "POST /api/v1/member_accounts" do
    it "crée un compte et lui attribue son code" do
      post "/api/v1/member_accounts",
           params: { member_account: { name: "Feyens", kind: "household",
                                       household: { name: "Feyens", kind: "resident" } } }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "code")).to match(/\ASRC-\d{4}\z/)
      expect(body.dig("meta", "created")).to be(true)
    end

    # Deux comptes « Feyens » et plus aucun total mensuel ne se recoupe.
    it "retrouve le compte existant plutôt que d'en créer un second" do
      post "/api/v1/member_accounts",
           params: { member_account: { name: "Feyens", kind: "household",
                                       household: { name: "Feyens" } } }.to_json, headers: headers
      code = body.dig("data", "code")

      expect {
        post "/api/v1/member_accounts",
             params: { member_account: { name: "Feyens", kind: "household", contact_email: "f@x.be",
                                         household: { name: "Feyens" } } }.to_json,
             headers: headers
      }.not_to change(MemberAccount, :count)

      expect(response).to have_http_status(:ok)
      expect(body.dig("data", "code")).to eq(code)
      expect(body.dig("data", "contact_email")).to eq("f@x.be")
      expect(body.dig("meta", "created")).to be(false)
    end

    it "refuse un compte sans nom" do
      post "/api/v1/member_accounts",
           params: { member_account: { kind: "household" } }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "crée le ménage à la volée puisque l'API ne sait pas en créer autrement" do
      expect {
        post "/api/v1/member_accounts", params: {
          member_account: { name: "Feyens", kind: "household",
                            household: { name: "Feyens", kind: "resident", moved_out_on: "2024-10-31" } }
        }.to_json, headers: headers
      }.to change(Household, :count).by(1)

      expect(Household.last.moved_out_on).to eq(Date.new(2024, 10, 31))
    end

    # Un ménage orphelin serait retrouvé par la requête suivante, et l'erreur
    # deviendrait invisible.
    it "ne laisse pas de ménage derrière lui quand le compte est refusé" do
      expect {
        post "/api/v1/member_accounts", params: {
          member_account: { name: "Feyens", kind: "human", household: { name: "Feyens" } }
        }.to_json, headers: headers
      }.not_to change(Household, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuse sans jeton" do
      post "/api/v1/member_accounts", params: { member_account: { name: "X", kind: "entity" } }.to_json,
                                      headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/member_accounts/:id" do
    let(:household) { Household.create!(name: "Sander", kind: "resident") }
    let!(:account) { MemberAccount.create!(kind: "household", household: household, name: "Sander") }

    it "clôt le compte d'un ménage parti sans toucher à son historique" do
      account.account_entries.create!(entry_date: Date.new(2022, 6, 30), amount_cents: 2715, label: "Conso bar")

      patch "/api/v1/member_accounts/#{account.id}",
            params: { member_account: { active: false } }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(account.reload.active).to be(false)
      expect(account.account_entries.count).to eq(1)
    end
  end

  describe "POST /api/v1/account_entries" do
    let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
    let!(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

    it "crée l'écriture et renvoie le solde du compte" do
      post "/api/v1/account_entries", params: {
        account_entry: { member_account_id: account.id, entry_date: "2023-06-30",
                         amount_cents: 24_000, flow: "charges", label: "Charges habitants",
                         source: "reprise", idempotency_key: "reprise:charges:SRC:2023-06" }
      }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(body.dig("data", "amount", "cents")).to eq(24_000)
      expect(body.dig("meta", "member_account_balance_cents")).to eq(24_000)
    end

    it "met à jour au lieu de dupliquer quand la clé d'idempotence revient" do
      params = { account_entry: { member_account_id: account.id, entry_date: "2023-06-30",
                                  amount_cents: 24_000, flow: "charges", label: "Charges habitants",
                                  idempotency_key: "reprise:charges:SRC:2023-06" } }
      post "/api/v1/account_entries", params: params.to_json, headers: headers

      expect {
        params[:account_entry][:amount_cents] = 30_000
        post "/api/v1/account_entries", params: params.to_json, headers: headers
      }.not_to change(AccountEntry, :count)

      expect(response).to have_http_status(:ok)
      expect(account.account_entries.sole.amount_cents).to eq(30_000)
    end

    # Sans clé, rien ne rattache la seconde requête à la première : on crée.
    # C'est voulu, et c'est pour ça que la reprise en fournit toujours une.
    it "crée deux écritures quand aucune clé n'est fournie" do
      params = { account_entry: { member_account_id: account.id, entry_date: "2023-06-30",
                                  amount_cents: 500, label: "Divers" } }

      expect {
        2.times { post "/api/v1/account_entries", params: params.to_json, headers: headers }
      }.to change(AccountEntry, :count).by(2)
    end

    it "sort en 409 sur une écriture verrouillée par un décompte émis" do
      entry = account.account_entries.create!(entry_date: Date.new(2026, 7, 15), amount_cents: 1500,
                                              label: "Conso bar", idempotency_key: "verrou")
      statement = Finance::IssueStatement.new(member_account: account, month: "2026-07").run!
      expect(entry.reload.account_statement_id).to eq(statement.id)

      post "/api/v1/account_entries", params: {
        account_entry: { member_account_id: account.id, entry_date: "2026-07-15",
                         amount_cents: 9999, idempotency_key: "verrou" }
      }.to_json, headers: headers

      expect(response).to have_http_status(:conflict)
      expect(entry.reload.amount_cents).to eq(1500)
    end

    it "refuse un montant nul" do
      post "/api/v1/account_entries", params: {
        account_entry: { member_account_id: account.id, entry_date: "2023-06-30", amount_cents: 0 }
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/member_accounts/:id/settlements" do
    let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
    let!(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

    before { account.account_entries.create!(entry_date: Date.new(2023, 6, 30), amount_cents: 24_000, label: "Charges") }

    it "crée UNE écriture négative et le règlement qui la documente" do
      expect {
        post "/api/v1/member_accounts/#{account.id}/settlements", params: {
          account_settlement: { amount_cents: 24_000, received_on: "2023-07-05",
                                method: "bank_transfer", reference: "reprise:2023-06" }
        }.to_json, headers: headers
      }.to change(AccountEntry, :count).by(1).and change(AccountSettlement, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(account.reload.balance_cents).to eq(0)
      expect(body.dig("meta", "member_account_balance_cents")).to eq(0)
    end

    it "n'encaisse pas deux fois la même référence" do
      params = { account_settlement: { amount_cents: 24_000, received_on: "2023-07-05",
                                       reference: "reprise:2023-06" } }
      post "/api/v1/member_accounts/#{account.id}/settlements", params: params.to_json, headers: headers

      expect {
        post "/api/v1/member_accounts/#{account.id}/settlements", params: params.to_json, headers: headers
      }.not_to change(AccountSettlement, :count)

      expect(response).to have_http_status(:ok)
      expect(account.reload.balance_cents).to eq(0)
    end

    it "refuse un montant négatif" do
      post "/api/v1/member_accounts/#{account.id}/settlements", params: {
        account_settlement: { amount_cents: -100, received_on: "2023-07-05" }
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/account_entries" do
    let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
    let!(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

    it "filtre par compte et par période" do
      account.account_entries.create!(entry_date: Date.new(2023, 1, 31), amount_cents: 100, label: "Jan")
      account.account_entries.create!(entry_date: Date.new(2023, 6, 30), amount_cents: 200, label: "Juin")

      get "/api/v1/account_entries", params: { member_account_id: account.id, from: "2023-03-01" },
                                     headers: headers

      expect(body["data"].map { |e| e["label"] }).to eq(["Juin"])
    end
  end

  describe "GET /api/v1/" do
    it "annonce les nouvelles ressources" do
      get "/api/v1/", headers: headers

      expect(body["resources"].map { |r| r["name"] }).to include("account_entries", "settlements")
    end
  end
end
