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

    it "libelle la ligne Stripe avec les dates du séjour (lisible client, pas un token)" do
      stay.update!(arrival_date: Date.new(2026, 9, 15), departure_date: Date.new(2026, 9, 17))
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      name = captured_args_for(payment)[:item][:name]
      expect(name).to eq("Séjour aux 4 Sources · du 15 septembre 2026 au 17 septembre 2026")
    end

    it "replie sur un libellé générique quand le séjour n'a pas de dates" do
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      expect(captured_args_for(payment)[:item][:name]).to eq("Séjour aux 4 Sources")
    end

    it "décrit un ACOMPTE (montant vs total) + la composition du séjour" do
      lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
      booking.update!(lodging: lodging)
      stay.stay_items.create!(bookable: booking)
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      description = captured_args_for(payment)[:item][:description]
      expect(description).to include("Acompte de 242,50 €")
      expect(description).to include("sur un séjour de 485 €") # no_cents_if_whole
      expect(description).to include("La Hulotte")
    end

    it "décrit un SOLDE quand un encaissement existe déjà" do
      Payment.create!(stay: stay, amount_cents: 24_250, status: "paid", payment_method: "card")
      payment = Payment.create!(stay: stay, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      expect(captured_args_for(payment)[:item][:description]).to include("Solde de 242,50 €")
    end

    it "décrit « Montant total du séjour » quand le paiement couvre tout" do
      payment = Payment.create!(stay: stay, amount_cents: 48_500,
                                status: "pending", payment_method: "card")

      expect(captured_args_for(payment)[:item][:description]).to include("Montant total du séjour")
    end

    it "pré-remplit l'email du client sur la page Stripe" do
      payment = Payment.create!(stay: stay, booking: booking, amount_cents: 24_250,
                                status: "pending", payment_method: "card")

      expect(captured_args_for(payment)[:customer_email]).to eq("stripe@example.com")
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
