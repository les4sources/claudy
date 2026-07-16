require "rails_helper"

# Epic #55, Phase 3 — POST /sejour/:token/payer-le-solde.
# Canal public scellé par le JETON du séjour (pas de Devise). Réutilise le
# mécanisme Stripe Checkout de l'acompte : on stubbe la session et on vérifie
# la redirection + le Payment créé.
RSpec.describe "Public::StayBalancePayments (POST /sejour/:token/payer-le-solde)", type: :request do
  let(:customer) { Customer.create!(email: "solde-req@example.com", customer_type: "individual") }

  let(:booking) do
    Booking.create!(firstname: "Sol", lastname: "Débiteur", from_date: Date.today + 10,
                    to_date: Date.today + 12, adults: 2, status: "confirmed",
                    booking_type: "lodging", price_cents: 40_000)
  end

  let(:stay) do
    s = Stay.create!(customer: customer, status: "pending", total_amount_cents: 40_000,
                     arrival_date: Date.today + 10, departure_date: Date.today + 12)
    s.stay_items.create!(bookable: booking)
    s
  end

  before do
    allow(StripeService.instance).to receive(:create_checkout_session)
      .and_return(OpenStruct.new(url: "https://checkout.stripe.test/solde-req"))
  end

  it "crée un paiement du solde exigible et redirige vers Stripe Checkout" do
    expect {
      post "/sejour/#{stay.token}/payer-le-solde"
    }.to change { stay.payments.pending.count }.by(1)

    expect(response).to redirect_to("https://checkout.stripe.test/solde-req")
    expect(stay.payments.pending.order(:created_at).last.amount_cents).to eq(40_000)
  end

  it "ne facture que l'exigible : activités confirmées incluses, pending exclues" do
    experience = Experience.create!(name: "Sauna", fixed_price_cents: 3_000, price_cents: 0)
    availability = ExperienceAvailability.create!(experience: experience, available_on: Date.today + 11, starts_at: "18:00")
    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "confirmed") # 3 000
    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "pending")   # 3 000 exclu
    stay.recompute_aggregates! # total prévu = 40 000 + 3 000 + 3 000 = 46 000

    post "/sejour/#{stay.token}/payer-le-solde"

    # Exigible = 40 000 (héberg.) + 3 000 (confirmée) = 43 000 (pending 3 000 exclue).
    expect(stay.payments.pending.order(:created_at).last.amount_cents).to eq(43_000)
  end

  it "redirige vers la page séjour avec une alerte quand rien n'est exigible" do
    Payment.create!(stay: stay, amount_cents: 40_000, status: "paid", payment_method: "card")

    post "/sejour/#{stay.token}/payer-le-solde"

    expect(response).to redirect_to(public_stay_path(stay.token))
    expect(flash[:alert]).to be_present
  end

  it "renvoie 404 sur un jeton inconnu (pas d'énumération d'IDs)" do
    post "/sejour/jeton-bidon/payer-le-solde"
    expect(response).to have_http_status(:not_found)
  end
end
