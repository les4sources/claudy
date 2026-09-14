require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 1 — « À affecter » se restreint à un compte ou à une famille
# de comptes. L'arrêté du mois y renvoie filtré sur Stripe quand une recette
# attend sa correspondance de catégorie.
RSpec.describe "Comptabilité — À affecter, filtré", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:stripe) do
    CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity,
                        general_account: build_general_account(code: "551000", name: "Stripe"),
                        stripe_account_key: "tranche_de_vie", stripe_mode: "ledger")
  end
  let!(:ligne_banque) { build_cash_entry(bank, label: "Virement Triodos") }
  let!(:ligne_stripe) { build_cash_entry(stripe, label: "Vente pain Stripe", amount_cents: 1_000) }

  before { sign_in user }

  it "montre toute la file sans filtre" do
    get finance_unallocated_cash_entries_path

    expect(response.body).to include("Virement Triodos")
    expect(response.body).to include("Vente pain Stripe")
  end

  it "restreint la file à une famille de comptes et le dit" do
    get finance_unallocated_cash_entries_path(kind: "stripe")

    expect(response.body).to include("Vente pain Stripe")
    expect(response.body).not_to include("Virement Triodos")
    expect(response.body).to include("Filtré sur")
    expect(response.body).to include("Voir toute la file")
  end

  it "restreint la file à un compte précis" do
    get finance_unallocated_cash_entries_path(cash_account_id: bank.id)

    expect(response.body).to include("Virement Triodos")
    expect(response.body).not_to include("Vente pain Stripe")
  end

  it "ignore un filtre de famille inconnu" do
    get finance_unallocated_cash_entries_path(kind: "licorne")

    expect(response.body).to include("Virement Triodos")
    expect(response.body).to include("Vente pain Stripe")
  end
end
