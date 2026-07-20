require "rails_helper"

# Fiche séjour (stays#show, partial `_details`) — section « Paiements ». Elle
# liste TOUS les paiements du séjour, encaissés (`paid`) ET en attente
# (`pending`), avec montant, moyen, statut (badge) et date. Alimentée par
# `Stay#payments` (union du lien direct `stay_id` et du canal booking).
RSpec.describe "Stays#show — section Paiements (epic #26 / #55)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)    { User.create!(email: "staff-pay@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(email: "pay@example.com", customer_type: "individual", first_name: "Ada", last_name: "Lovelace") }

  let(:from) { Date.today + 30 }
  let(:to)   { Date.today + 32 }

  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: from, departure_date: to, total_amount_cents: 12_000)
  end

  before do
    # Un paiement encaissé et un paiement en attente, rattachés directement au séjour.
    Payment.create!(stay: stay, amount_cents: 5_000, payment_method: "cash", status: "paid")
    Payment.create!(stay: stay, amount_cents: 7_000, payment_method: "bank_transfer", status: "pending")
    sign_in admin
    get stay_path(stay)
  end

  it "répond OK et affiche l'en-tête de la section Paiements" do
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Paiements")
  end

  it "affiche le paiement ENCAISSÉ (montant, moyen, badge Payé)" do
    expect(response.body).to include("50,00") # 5 000 cents
    expect(response.body).to include("Liquide")
    expect(response.body).to include("Payé")
  end

  it "affiche le paiement EN ATTENTE (montant, moyen, badge En attente)" do
    expect(response.body).to include("70,00") # 7 000 cents
    expect(response.body).to include("Virement")
    expect(response.body).to include("En attente")
  end

  context "séjour sans aucun paiement" do
    let(:empty_stay) do
      Stay.create!(customer: customer, source: "manual", status: "confirmed",
                   arrival_date: from, departure_date: to, total_amount_cents: 0)
    end

    it "affiche l'état vide de la section" do
      get stay_path(empty_stay)
      expect(response.body).to include("Aucun paiement enregistré pour ce séjour.")
    end
  end
end
