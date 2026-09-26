require "rails_helper"

# Séjour réservé via Airbnb ou Booking.com (Michael, 2026-09-26) : le client a
# vu et payé son tarif sur la plateforme. La page publique ne lui montre donc ni
# le prix de son hébergement, ni total, ni paiement.
RSpec.describe "Public /sejour/:token — séjour Airbnb / Booking.com", type: :request do
  let(:customer) { Customer.create!(email: "voyageur@example.com", first_name: "Léa") }
  let(:lodging)  { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  def build_stay(source: "manual", platform: "web")
    booking = Booking.create!(firstname: "Léa", lastname: "Martin", lodging: lodging,
                              from_date: Date.today + 10, to_date: Date.today + 12,
                              adults: 2, children: 1, status: "confirmed",
                              booking_type: "lodging", price_cents: 48_500, platform: platform)
    stay = Stay.create!(customer: customer, source: source, status: "confirmed",
                        arrival_date: Date.today + 10, departure_date: Date.today + 12,
                        total_amount_cents: 48_500)
    stay.stay_items.create!(bookable: booking)
    stay
  end

  def expect_no_pricing_nor_payment
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-stay-items="true"')
    expect(response.body).not_to include("485")
    expect(response.body).not_to include('data-stay-total="true"')
    expect(response.body).not_to include(I18n.t("public.stays.payments.heading"))
    expect(response.body).not_to include('data-stay-balance-cta="true"')
    expect(response.body).not_to include("translation missing")
  end

  it "masque tarif et paiements pour un séjour au canal OTA" do
    get "/sejour/#{build_stay(source: 'ota').token}"

    expect_no_pricing_nor_payment
  end

  it "masque tarif et paiements quand le booking vient d'Airbnb" do
    get "/sejour/#{build_stay(platform: 'airbnb').token}"

    expect_no_pricing_nor_payment
  end

  it "masque tarif et paiements quand le booking vient de Booking.com" do
    get "/sejour/#{build_stay(platform: 'bookingdotcom').token}"

    expect_no_pricing_nor_payment
  end

  it "garde tarif et paiements pour un séjour réservé en direct" do
    get "/sejour/#{build_stay.token}"

    expect(response.body).to include('data-stay-total="true"')
    expect(response.body).to include(I18n.t("public.stays.payments.heading"))
  end

  it "refuse le paiement du solde d'un séjour OTA" do
    stay = build_stay(source: "ota")

    expect { post "/sejour/#{stay.token}/payer-le-solde" }.not_to change(Payment, :count)
    expect(response).to redirect_to("/sejour/#{stay.token}")
  end
end
