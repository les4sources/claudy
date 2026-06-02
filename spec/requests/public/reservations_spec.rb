require "rails_helper"

RSpec.describe "Public::Reservations (/reservation)", type: :request do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival) { (Date.today + 40).iso8601 }
  let(:departure) { (Date.today + 42).iso8601 }

  let(:contact_params) do
    {
      reservation: {
        lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure,
        dogs_count: 1, first_name: "Alex", last_name: "Durand",
        email: "alex@example.com", phone: "+32470000000"
      }
    }
  end

  describe "accessibilité publique (AC-T2-01)" do
    it "GET /reservation redirige vers le formulaire de composition" do
      get "/reservation"
      expect(response).to redirect_to("/reservation/composer")
    end
  end

  describe "devis temps-réel (AC-T2-10/11)" do
    it "POST /reservation/devis répond en Turbo Stream et affiche le total TVAC" do
      post "/reservation/devis", params: { reservation: { lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure } },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include("aucune TVA supplémentaire")
    end
  end

  describe "champ chien obligatoire (AC-T2-09)" do
    it "échoue sans email/contact valide et n'écrit rien" do
      post "/reservation/coordonnees", params: { reservation: { lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure, dogs_count: 1, first_name: "Sans", email: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Stay.count).to eq(0)
    end
  end

  describe "soumission → Stripe (Q5 — AC-T2-19) avec Stripe stubbé" do
    before do
      session_double = OpenStruct.new(url: "https://checkout.stripe.test/session/abc")
      allow(StripeService.instance).to receive(:create_checkout_session).and_return(session_double)
    end

    it "crée un Stay pending et redirige vers Stripe (pas d'auto-confirm)" do
      expect {
        post "/reservation/coordonnees", params: contact_params
      }.to change(Stay, :count).by(1)

      stay = Stay.last
      expect(stay.status).to eq("pending")
      expect(stay.source).to eq("reservation")
      expect(response).to redirect_to("https://checkout.stripe.test/session/abc")
    end

    it "enqueue l'email de récap avec lien token (AC-T2-21)" do
      expect {
        post "/reservation/coordonnees", params: contact_params
      }.to have_enqueued_mail(ReservationMailer, :confirmation_request)
    end

    it "même email → un seul Customer, plusieurs Stays (AC-T2-18)" do
      post "/reservation/coordonnees", params: contact_params
      post "/reservation/coordonnees", params: contact_params
      expect(Customer.where(email: "alex@example.com").count).to eq(1)
      expect(Customer.find_by(email: "alex@example.com").stays.count).to eq(2)
    end
  end

  describe "webhook Stripe → reste pending (AC-T2-19/20, ISC-4)" do
    before do
      session_double = OpenStruct.new(url: "https://checkout.stripe.test/session/abc")
      allow(StripeService.instance).to receive(:create_checkout_session).and_return(session_double)
    end

    it "le paiement validé ne passe JAMAIS le Stay en confirmed automatiquement" do
      post "/reservation/coordonnees", params: contact_params
      stay = Stay.last
      payment = stay.payments.first
      expect(payment).to be_present

      # Simule l'effet du webhook (checkout.session.completed) sans signature.
      Stripe::CompletedCheckoutService.new(payment: payment).run!(
        stripe_checkout_session_id: "cs_test_123",
        stripe_payment_intent_id: "pi_test_123"
      )

      payment.reload
      stay.reload
      expect(payment.status).to eq("paid")
      expect(stay.status).to eq("pending") # validation manuelle Malau requise
    end
  end
end
