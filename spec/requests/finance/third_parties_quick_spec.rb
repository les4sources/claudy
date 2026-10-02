require "rails_helper"

# Créer un fournisseur depuis le formulaire d'une facture (2026-09-30) : le
# contrôleur `supplier-quick-create` poste ici et attend du JSON.
RSpec.describe "Comptabilité — Tiers, création express", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "tresoriere@les4sources.be", password: "password123") }
  let(:headers) { { "Accept" => "application/json" } }

  before { sign_in user }

  it "crée un fournisseur et renvoie de quoi le sélectionner" do
    post quick_finance_third_parties_path, headers: headers, params: {
      third_party: { name: "Ferme de Grange SRL", vat_number: "BE0727713318", iban: "BE68 5390 0754 7034", email: "" }
    }

    expect(response).to have_http_status(:created)
    tiers = ThirdParty.find(response.parsed_body["id"])
    expect(tiers).to have_attributes(name: "Ferme de Grange SRL", kind: "supplier", iban: "BE68539007547034")
    expect(response.parsed_body["name"]).to eq("Ferme de Grange SRL")
  end

  it "renvoie le fournisseur existant plutôt que d'en créer un second avec la même TVA" do
    grange = ThirdParty.create!(name: "Ferme de Grange", kind: "supplier", vat_number: "BE 0727.713.318")

    expect do
      post quick_finance_third_parties_path, headers: headers, params: { third_party: { name: "FERME DE GRANGE SRL", vat_number: "BE0727713318" } }
    end.not_to change(ThirdParty, :count)

    expect(response.parsed_body).to include("id" => grange.id, "name" => "Ferme de Grange", "existing" => true)
  end

  it "refuse un fournisseur sans nom ou avec un IBAN faux, et dit pourquoi" do
    post quick_finance_third_parties_path, headers: headers, params: { third_party: { name: "", iban: "BE00 1234" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"].join).to include("IBAN")
  end
end
