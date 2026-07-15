require "rails_helper"

# Epic #26, Phase 2 — le Checkout Stripe est Stay-first : le client revient sur
# la page séjour, avec repli sur la page booking pour les paiements historiques.
RSpec.describe Payments::PayService do
  let(:customer) { Customer.create!(email: "stripe@example.com", customer_type: "individual") }
  let(:booking) do
    Booking.create!(firstname: "Léa", from_date: Date.today + 10, to_date: Date.today + 12,
                    adults: 2, status: "pending", price_cents: 48_500)
  end
  let(:stay) do
    Stay.create!(customer: customer, source: "reservation", status: "pending",
                 total_amount_cents: 48_500)
  end

  # On n'appelle pas Stripe : on intercepte la session de checkout et on inspecte
  # les arguments que le service lui passe.
  def captured_args_for(payment)
    captured = nil
    fake_session = double("checkout_session", url: "https://checkout.stripe.test/session")

    allow(StripeService.instance).to receive(:create_checkout_session) do |args|
      captured = args
      fake_session
    end

    expect(described_class.new(payment_id: payment.id).run).to be(true)
    captured
  end

  context "paiement rattaché à un séjour (canal B2C)" do
    it "renvoie le client sur /sejour/:token en succès ET en annulation" do
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      args = captured_args_for(payment)
      expected = "/sejour/#{stay.reload.token}"

      expect(args[:success_url]).to include(expected)
      expect(args[:cancel_url]).to include(expected)
    end

    it "libelle la ligne Stripe « Séjour #<token> »" do
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      expect(captured_args_for(payment)[:item][:name]).to eq("Séjour ##{stay.reload.token}")
    end

    it "fonctionne pour un séjour SANS hébergement (aucun booking)" do
      payment = Payment.create!(stay: stay, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      args = captured_args_for(payment)

      expect(payment.booking).to be_nil
      expect(args[:success_url]).to include("/sejour/#{stay.reload.token}")
    end
  end

  context "paiement historique (booking seul, pas de stay)" do
    it "retombe sur la page booking" do
      # Donnée LEGACY : un Payment persisté avant le verrouillage Phase 4, donc
      # sans stay_id. On contourne la validation (save(validate: false)) pour
      # reproduire fidèlement l'état en base — le repli production sur la page
      # booking doit rester couvert pour ces enregistrements historiques.
      payment = Payment.new(booking: booking, amount_cents: 24_250,
                            status: "pending", payment_method: "card")
      payment.save!(validate: false)

      args = captured_args_for(payment)

      expect(args[:success_url]).to include("/reservation/#{booking.token}")
      expect(args[:item][:name]).to eq("Réservation ##{booking.token}")
    end
  end
end
