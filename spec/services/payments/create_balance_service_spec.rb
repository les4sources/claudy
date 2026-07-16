require "rails_helper"

# Epic #55, Phase 3 — paiement du SOLDE exigible du séjour.
#
# Le montant réglé = montant EXIGIBLE = (hébergement/espaces + activités
# CONFIRMED) − encaissé. Les activités `pending` (non validées) en sont exclues.
# On n'appelle jamais Stripe : on stubbe la session de checkout (même mécanisme
# que l'acompte, epic #26) et on inspecte le Payment créé + le montant transmis.
#
# NB : on pose `total_amount_cents` DIRECTEMENT (= « total prévu » = hébergement
# + activités actives) plutôt que via `recompute_aggregates!`, pour tester le
# calcul de l'exigible sans dépendre d'items d'hébergement réels.
RSpec.describe Payments::CreateBalanceService do
  let(:customer) { Customer.create!(email: "solde@example.com", customer_type: "individual") }

  let(:experience) { Experience.create!(name: "Atelier pain", fixed_price_cents: 5_000, price_cents: 1_500) }
  let(:availability) do
    ExperienceAvailability.create!(experience: experience, available_on: Date.new(2026, 7, 10), starts_at: "10:00")
  end

  def build_stay(total_cents:)
    Stay.create!(customer: customer, source: "reservation", status: "pending",
                 total_amount_cents: total_cents,
                 arrival_date: Date.new(2026, 7, 1), departure_date: Date.new(2026, 7, 3))
  end

  def stub_checkout!
    fake_session = double("checkout_session", url: "https://checkout.stripe.test/solde")
    allow(StripeService.instance).to receive(:create_checkout_session).and_return(fake_session)
  end

  describe "calcul du montant exigible" do
    it "facture hébergement + activités CONFIRMED, exclut les PENDING, déduit l'encaissé" do
      # Total prévu = 20 000 (héberg.) + 8 000 (confirmée) + 6 500 (pending) = 34 500.
      stay = build_stay(total_cents: 34_500)
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "confirmed") # 5 000 + 1 500×2 = 8 000
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 1, status: "pending")   # 5 000 + 1 500   = 6 500
      Payment.create!(stay: stay, amount_cents: 10_000, status: "paid", payment_method: "card")

      stub_checkout!
      service = described_class.new(stay: stay.reload)
      expect(service.run).to be(true)

      # Exigible = (34 500 − 6 500 pending) − 10 000 encaissé = 18 000.
      expect(service.payment.amount_cents).to eq(18_000)
      expect(service.payment.stay_id).to eq(stay.id)
      expect(service.payment.status).to eq("pending")
      expect(service.checkout_session_url).to eq("https://checkout.stripe.test/solde")
    end

    it "n'exige rien quand seules des activités PENDING restent une fois l'exigible réglé" do
      # Total prévu = 20 000 (héberg.) + 6 500 (pending) = 26 500.
      stay = build_stay(total_cents: 26_500)
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 1, status: "pending")
      Payment.create!(stay: stay, amount_cents: 20_000, status: "paid", payment_method: "card")

      # Exigible = (26 500 − 6 500 pending) − 20 000 encaissé = 0.
      expect(stay.reload.balance_due_cents).to eq(0)

      service = described_class.new(stay: stay)
      expect(service.run).to be(false)
      expect(service.error_message).to match(/soldé|exigible/i)
    end
  end

  describe "réutilisation / création du paiement" do
    it "crée un unique paiement pending ancré sur le Stay" do
      stay = build_stay(total_cents: 30_000)
      stub_checkout!

      expect {
        expect(described_class.new(stay: stay).run).to be(true)
      }.to change { stay.payments.pending.count }.by(1)
    end

    it "réutilise le paiement pending existant en réalignant son montant (anti-doublon)" do
      stay = build_stay(total_cents: 30_000)
      existing = Payment.create!(stay: stay, amount_cents: 12_000, status: "pending", payment_method: "card")
      stub_checkout!

      expect {
        described_class.new(stay: stay.reload).run
      }.not_to change { stay.payments.pending.count }

      expect(existing.reload.amount_cents).to eq(30_000)
    end
  end
end
