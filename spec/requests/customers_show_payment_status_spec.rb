require "rails_helper"

# Fiche client (customers#show) — chaque séjour listé affiche SON STATUT DE
# PAIEMENT (`Stay#payment_status`), au même badge que la page client. Sans lui,
# la liste montre un montant sans jamais dire s'il a été encaissé.
RSpec.describe "Customers#show — statut de paiement des séjours", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)    { User.create!(email: "paiement-fiche@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(email: "paiement-client@example.com", customer_type: "individual", first_name: "Ada", last_name: "Lovelace") }

  def stay_with(payment_status:, arrival:, amount_cents: 48_500)
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: arrival, departure_date: arrival + 2,
                 total_amount_cents: amount_cents, payment_status: payment_status)
  end

  # Un séjour par statut : deux à venir, un passé — la vue rend les deux listes.
  let!(:paid)      { stay_with(payment_status: "paid", arrival: Date.today + 30) }
  let!(:partially) { stay_with(payment_status: "partially_paid", arrival: Date.today + 40) }
  let!(:pending)   { stay_with(payment_status: "pending", arrival: Date.today - 40) }

  before do
    sign_in admin
    get customer_path(customer)
  end

  it "répond OK" do
    expect(response).to have_http_status(:ok)
  end

  it "affiche « Payé » pour un séjour soldé" do
    expect(response.body).to include(I18n.t("public.stays.payment_status.paid"))
  end

  it "affiche « Partiellement payé » pour un séjour partiellement réglé" do
    expect(response.body).to include(I18n.t("public.stays.payment_status.partially_paid"))
  end

  it "affiche « En attente de paiement » pour un séjour passé non réglé" do
    expect(response.body).to include(I18n.t("public.stays.payment_status.pending"))
  end

  it "pose un badge de paiement par séjour listé" do
    badges = response.body.scan(/rounded-full px-2\.5 py-0\.5 text-xs font-medium (?:bg-green-100 text-green-800|bg-amber-100 text-amber-800|bg-gray-100 text-gray-700)">(?:#{Regexp.union(
      I18n.t("public.stays.payment_status.paid"),
      I18n.t("public.stays.payment_status.partially_paid"),
      I18n.t("public.stays.payment_status.pending")
    )})</).size
    expect(badges).to eq(3)
  end
end
