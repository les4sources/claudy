require "rails_helper"

# Un lien d'acompte d'un séjour ANNULÉ ne doit plus mener à Stripe. Les
# paiements en attente sont soft-deletés à l'annulation (le lien répond alors
# 404) ; un paiement encore vivant sur un séjour annulé — données antérieures à
# cette règle — est renvoyé vers la page séjour avec un message.
RSpec.describe "Lien de paiement d'un séjour annulé", type: :request do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }
  let(:stay) do
    Stay.create!(customer: customer, source: "reservation", status: "canceled",
                 arrival_date: Date.today + 30, departure_date: Date.today + 32,
                 total_amount_cents: 74_500)
  end

  it "renvoie vers la page séjour au lieu de Stripe" do
    payment = Payment.create!(stay: stay, amount_cents: 37_250, status: "pending", payment_method: "card")

    get pay_public_payment_path(payment)

    expect(response).to redirect_to(public_stay_path(stay.token))
    expect(flash[:alert]).to include("annulé")
  end
end
