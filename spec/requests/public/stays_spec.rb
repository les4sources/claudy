require "rails_helper"

RSpec.describe "Public::Stays (/sejour/:token)", type: :request do
  let(:customer) { Customer.create!(email: "stay@example.com", customer_type: "individual") }

  let(:booking) do
    Booking.create!(firstname: "Alex", lastname: "Durand", from_date: Date.today + 10,
                    to_date: Date.today + 12, adults: 2, status: "pending",
                    booking_type: "lodging", price_cents: 48_500)
  end

  let(:stay) do
    s = Stay.create!(customer: customer, status: "pending", total_amount_cents: 48_500,
                     arrival_date: Date.today + 10, departure_date: Date.today + 12)
    s.stay_items.create!(bookable: booking)
    s
  end

  describe "GET /sejour/:token" do
    it "rend la page sans authentification Devise" do
      get "/sejour/#{stay.token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Votre séjour aux 4 Sources")
      expect(response.body).to include("data-stay-items")
    end

    it "affiche le statut de paiement du séjour" do
      get "/sejour/#{stay.token}"
      expect(response.body).to include("En attente de paiement")

      Payment.create!(booking: booking, stay: stay, amount_cents: 48_500, status: "paid", payment_method: "card")
      stay.set_payment_status

      get "/sejour/#{stay.token}"
      expect(response.body).to include("Payé")
    end

    it "expose le CTA de paiement Stripe pour chaque paiement en attente" do
      payment = Payment.create!(booking: booking, stay: stay, amount_cents: 48_500,
                                status: "pending", payment_method: "card")

      get "/sejour/#{stay.token}"

      expect(response.body).to include('data-stay-payments="pending"')
      expect(response.body).to include(pay_public_payment_path(payment))
    end

    it "liste les paiements reçus" do
      Payment.create!(booking: booking, stay: stay, amount_cents: 48_500, status: "paid", payment_method: "card")

      get "/sejour/#{stay.token}"

      expect(response.body).to include('data-stay-payments="paid"')
    end

    it "renvoie 404 sur un token inconnu" do
      get "/sejour/inconnu"
      expect(response).to have_http_status(:not_found)
    end
  end
end
