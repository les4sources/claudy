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

    it "affiche la note PUBLIQUE du séjour et JAMAIS la note interne" do
      stay.update!(notes: "SECRET INTERNE À NE PAS DIVULGUER")
      stay.public_notes = "<div>Bon séjour à vous et à bientôt</div>"
      stay.save!

      get "/sejour/#{stay.token}"

      expect(response.body).to include("Bon séjour à vous et à bientôt")
      expect(response.body).not_to include("SECRET INTERNE")
    end
  end

  # Epic #55, Phase 3 — ventilation exigible + bouton « Payer le solde ».
  describe "solde exigible (/sejour/:token)" do
    it "affiche le bouton « Payer le solde » quand l'exigible > 0 et aucun paiement en attente" do
      get "/sejour/#{stay.token}"

      expect(response.body).to include('data-stay-balance="true"')
      expect(response.body).to include('data-stay-balance-cta="true"')
      expect(response.body).to include(public_stay_balance_payment_path(stay.token))
    end

    it "masque le bouton quand l'exigible est nul (séjour soldé)" do
      Payment.create!(booking: booking, stay: stay, amount_cents: 48_500, status: "paid", payment_method: "card")

      get "/sejour/#{stay.token}"

      expect(response.body).not_to include('data-stay-balance-cta="true"')
    end

    it "masque le bouton quand un paiement est déjà en attente (l'acompte a son propre CTA)" do
      Payment.create!(booking: booking, stay: stay, amount_cents: 24_250, status: "pending", payment_method: "card")

      get "/sejour/#{stay.token}"

      expect(response.body).not_to include('data-stay-balance-cta="true"')
      # Le CTA générique de l'acompte, lui, reste présent.
      expect(response.body).to include('data-stay-payments="pending"')
    end

    it "distingue les activités validées (exigibles) des activités en attente (non exigibles)" do
      experience = Experience.create!(name: "Sauna", fixed_price_cents: 3_000, price_cents: 0)
      availability = ExperienceAvailability.create!(experience: experience, available_on: Date.today + 11, starts_at: "18:00")
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "confirmed")
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "pending")
      stay.recompute_aggregates!

      get "/sejour/#{stay.token}"

      expect(response.body).to include('data-balance-pending="true"')
      expect(response.body).to include(I18n.t("public.stays.balance.experiences_confirmed"))
    end
  end

  # Issue #79 — le funnel public persiste camping/van/repas : la page /sejour doit
  # les afficher en lignes distinctes (repas inclus, bien que non `stay_items`) et
  # rester cohérente (décomposition qui somme au total).
  describe "GET /sejour/:token — composition camping + repas (issue #79)" do
    it "affiche les lignes camping et repas" do
      camping = CampingBooking.create!(firstname: "Alex", from_date: Date.today + 10,
                                       to_date: Date.today + 12, people: 3, status: "pending",
                                       kind: "tente", price_cents: 4_500)
      stay.stay_items.create!(bookable: camping)
      stay.meal_orders.create!(kind: "buffet", people: 4, price_cents: 4_800) # sans date
      stay.update!(total_amount_cents: 48_500 + 4_500 + 4_800)

      get "/sejour/#{stay.token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("public.stays.items.camping"))
      expect(response.body).to include(I18n.t("public.stays.items.meal"))
    end
  end
end
