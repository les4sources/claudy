require "rails_helper"

# Un paiement de COWORKING n'a ni booking ni séjour (il est ancré sur un
# CoworkingPack). `linked_path` appelait pourtant `stay_path(nil)` : une seule
# ligne de ce type faisait tomber TOUTE la page /payments en
# UrlGenerationError.
RSpec.describe "Paiements — paiement sans séjour", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-paiements@les4sources.be", password: "password123") }
  before { sign_in user }

  def payment(**attrs)
    Payment.create!({ amount_cents: 2_000, status: "pending", payment_method: "transfer" }.merge(attrs))
  end

  def coworking_payment
    customer = Customer.create!(email: "cwk@example.com", first_name: "Cléo", last_name: "Coworking")
    pack = CoworkingPack.create!(customer: customer, days_total: 5, payment_method: "card")
    payment(coworking_pack: pack)
    pack
  end

  it "rend la page malgré un paiement de coworking (sans séjour)" do
    coworking_payment
    get payments_path
    expect(response).to have_http_status(:ok)
  end

  it "relie le paiement de coworking à son pack, et pas à un séjour vide" do
    pack = coworking_payment
    get payments_path
    expect(response.body).to include(%(href="#{coworking_pack_path(pack)}"))
    expect(response.body).to include("Cléo Coworking")
    expect(response.body).not_to match(%r{href="/stays/"})
  end

  it "conserve le lien quand le paiement porte bien un séjour" do
    customer = Customer.create!(email: "lien@example.com", first_name: "Ana", last_name: "Lien")
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: Date.today + 3, departure_date: Date.today + 5)
    payment(stay: stay)

    get payments_path
    expect(response.body).to include(%(href="#{stay_path(stay)}"))
  end
end
