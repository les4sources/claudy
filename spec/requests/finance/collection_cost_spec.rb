require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

RSpec.describe "Finances > Coût d'encaissement", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let(:stripe_general) { build_general_account(code: "551000", name: "Stripe") }
  let!(:cash_account) do
    CashAccount.create!(name: "Stripe", kind: "stripe", legal_entity: entity, general_account: stripe_general)
  end

  before { sign_in user }

  it "dit ce que coûte la carte, et rappelle que le virement ne coûte rien" do
    payout = StripePayout.create!(account_key: "claudy", cash_account: cash_account, stripe_id: "po_1",
                                  amount_cents: 126_900, arrival_date: Date.current)
    StripeBalanceTransaction.create!(stripe_payout: payout, stripe_id: "txn_1", kind: "charge",
                                     gross_cents: 130_000, fee_cents: 3_100, net_cents: 126_900)

    get finance_collection_cost_path(from: Date.current.beginning_of_year, to: Date.current.end_of_year)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Claudy")
    expect(response.body).to include("ne coûte aucune commission")
    expect(response.body).to include("2,38 %")
  end

  it "invite à lancer la synchronisation quand il n'y a rien" do
    get finance_collection_cost_path

    expect(response.body).to include("stripe:sync_payouts")
  end
end
