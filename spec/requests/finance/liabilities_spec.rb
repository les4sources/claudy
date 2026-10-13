require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Comptabilité > Fournisseurs > Dettes et litiges (2026-10-13).
RSpec.describe "Comptabilité > Dettes et litiges", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-dettes@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:yvoir) { ThirdParty.create!(name: "Commune d'Yvoir", kind: "supplier") }

  before { sign_in user }

  it "dit son vide, ici et sur la page Comptabilité" do
    get finance_liabilities_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aucune dette ni aucun litige en cours")

    get finance_accounting_path
    expect(response.body).to include("Aucune dette ni aucun litige sans facture")
  end

  it "enregistre la taxe d'Yvoir en retenant le haut de la fourchette, puis la montre partout" do
    post finance_liabilities_path, params: { liability: {
      label: "Taxe communale d'hébergement 2021-2025", kind: "dispute", legal_entity_id: entity.id,
      third_party_id: yvoir.id, claimed: "12 000", low: "6 000", high: "12 000", retained: "",
      expected_on: (Date.current + 30).iso8601, installments: "1", status: "open"
    } }

    expect(response).to redirect_to(finance_liabilities_path)
    taxe = Liability.last
    expect(taxe.retained_cents).to eq(1_200_000)
    expect(taxe.third_party).to eq(yvoir)

    get finance_liabilities_path
    expect(response.body).to include("Taxe communale d&#39;hébergement 2021-2025", "12 000 €", "6 000 € – 12 000 €")

    get finance_accounting_path
    expect(response.body).to include("1 dette(s) ou litige(s) sans facture : 12 000 € retenus")

    get finance_treasury_path
    expect(response.body).to include("data-liability-id=\"#{taxe.id}\"")
  end

  it "refuse un retenu hors de la fourchette et le dit" do
    post finance_liabilities_path, params: { liability: {
      label: "Taxe", kind: "dispute", legal_entity_id: entity.id, low: "6000", high: "12000", retained: "15000",
      installments: "1", status: "open"
    } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("dépasse le haut de la fourchette")
    expect(Liability.count).to eq(0)
  end

  it "solde une dette, qui passe dans l'historique, puis supprime une erreur d'encodage" do
    dette = Liability.create!(legal_entity: entity, label: "Arriéré Voo", retained_cents: 20_000)

    patch finance_liability_path(dette), params: { liability: { status: "settled" } }
    expect(response).to redirect_to(finance_liabilities_path)
    expect(dette.reload.closed_on).to eq(Date.current)

    get finance_liabilities_path
    expect(response.body).to include("Soldées ou abandonnées", "soldée")

    delete finance_liability_path(dette)
    expect(Liability.count).to eq(0)
  end
end
