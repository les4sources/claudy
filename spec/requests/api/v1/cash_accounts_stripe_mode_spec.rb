require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 1 — le mode d'un compte Stripe se règle par l'API agent, et se
# lit dans sa représentation. Sans ça, basculer Tranches de Vie en grand livre
# demanderait une console de production.
RSpec.describe "API v1 — mode Stripe d'un compte de trésorerie", type: :request do
  include FinanceBuilders

  let(:token) { "jeton-de-test" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  before { ENV["AGENT_API_TOKEN"] = token }
  after { ENV.delete("AGENT_API_TOKEN") }

  def body = JSON.parse(response.body)

  let(:entity) { build_legal_entity }
  let!(:general) { build_general_account(code: "551000", name: "Stripe") }
  let!(:account) do
    CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity,
                        general_account: general, stripe_account_key: "tranche_de_vie")
  end

  it "expose le mode et la clé du compte" do
    get "/api/v1/cash_accounts/#{account.id}", headers: headers

    expect(response).to have_http_status(:ok)
    expect(body["data"]["stripe_mode"]).to eq("per_payout")
    expect(body["data"]["stripe_account_key"]).to eq("tranche_de_vie")
  end

  it "bascule le compte en grand livre" do
    patch "/api/v1/cash_accounts/#{account.id}",
          params: { cash_account: { stripe_mode: "ledger" } }.to_json, headers: headers

    expect(response).to have_http_status(:ok)
    expect(account.reload.stripe_mode).to eq("ledger")
    expect(body["data"]["stripe_mode"]).to eq("ledger")
  end

  it "refuse un mode hors liste" do
    patch "/api/v1/cash_accounts/#{account.id}",
          params: { cash_account: { stripe_mode: "magique" } }.to_json, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.stripe_mode).to eq("per_payout")
  end
end
