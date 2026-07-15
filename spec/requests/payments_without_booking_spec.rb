require "rails_helper"

# Epic #26, Phase 2 — un paiement peut désormais n'avoir aucun booking (séjour
# sans hébergement). L'admin liste TOUS les paiements : sans garde-fou, la liste
# faisait un `booking_path(nil)` et plantait.
RSpec.describe "Admin — paiements sans booking", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(email: "camping@example.com", customer_type: "individual") }
  let(:stay) do
    Stay.create!(customer: customer, source: "reservation", status: "pending",
                 arrival_date: Date.today + 10, departure_date: Date.today + 12,
                 total_amount_cents: 12_000)
  end
  let!(:payment) do
    Payment.create!(stay: stay, amount_cents: 6_000, status: "pending", payment_method: "card")
  end

  before { sign_in user }

  it "affiche la liste des paiements sans planter" do
    get payments_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(stay_path(stay))
  end

  it "affiche le détail d'un paiement sans booking, rattaché au séjour" do
    get payment_path(payment)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Séjour")
    expect(response.body).to include(stay_path(stay))
  end
end
