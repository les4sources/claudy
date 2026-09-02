require "rails_helper"

RSpec.describe "Public::Reservations (/reservation)", type: :request, queue_adapter: :test do
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
      expect(response).to redirect_to("/reservation/sejour")
    end
  end

  describe "étape 1 — contrainte départ > arrivée (#40)" do
    it "GET /reservation/sejour n'affiche aucune erreur de dates au premier affichage" do
      get "/reservation/sejour"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-dates-error")
    end

    it "POST avec un départ antérieur à l'arrivée re-rend l'étape 1 avec une erreur" do
      post "/reservation/sejour", params: { reservation: { arrival_date: departure, departure_date: arrival, adults: 2 } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("data-dates-error")
      expect(response.body).to include("postérieure à la date d&#39;arrivée")
    end

    it "POST avec un départ égal à l'arrivée re-rend l'étape 1 avec une erreur" do
      post "/reservation/sejour", params: { reservation: { arrival_date: arrival, departure_date: arrival, adults: 2 } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("data-dates-error")
    end

    it "POST avec des dates valides avance vers l'étape 2 (comportement préservé)" do
      post "/reservation/sejour", params: { reservation: { arrival_date: arrival, departure_date: departure, adults: 2 } }

      expect(response).to redirect_to("/reservation/composer")
    end

    it "ne corrompt pas un draft valide déjà en session (anti-régression)" do
      post "/reservation/sejour", params: { reservation: { arrival_date: arrival, departure_date: departure, adults: 2 } }
      post "/reservation/sejour", params: { reservation: { arrival_date: departure, departure_date: arrival, adults: 2 } }
      expect(response).to have_http_status(:unprocessable_entity)

      # L'étape 2 reste alimentée par les dates valides mémorisées.
      get "/reservation/composer"
      expect(response.body).to include(I18n.l(Date.parse(arrival), format: :long))
      expect(response.body).not_to include("Choisissez vos dates à l'étape précédente")
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

  # Issue #215 — la soumission n'appelle plus Stripe : elle enregistre une
  # demande que le Pôle Accueil pré-confirmera.
  describe "soumission (Q5 — AC-T2-19)" do
    it "crée un Stay pending sans paiement et renvoie sur la page séjour" do
      expect {
        post "/reservation/coordonnees", params: contact_params
      }.to change(Stay, :count).by(1).and change(Payment, :count).by(0)

      stay = Stay.last
      expect(stay.status).to eq("pending")
      expect(stay.source).to eq("reservation")
      expect(response).to redirect_to("/sejour/#{stay.token}")
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

  # AC-T2-19/20 réécrit par l'issue #215. La règle « le paiement ne confirme
  # jamais » tenait tant que le client pouvait payer AVANT tout regard humain :
  # il fallait bien que quelqu'un valide ensuite. Depuis l'inversion de l'ordre,
  # le regard humain a déjà eu lieu (c'est la pré-confirmation), et c'est
  # l'encaissement qui confirme.
  describe "webhook Stripe → confirmation automatique (issue #215)" do
    it "le paiement de l'acompte confirme le séjour pré-confirmé" do
      post "/reservation/coordonnees", params: contact_params
      stay = Stay.last
      expect(stay.payments).to be_empty # rien n'est dû tant que le Pôle Accueil n'a pas regardé

      expect(Stays::PreConfirmer.new(stay: stay, amount_cents: 20_000).run).to be(true)
      payment = stay.reload.payments.first
      expect(stay.status).to eq("pre_confirmed")

      # Simule l'effet du webhook (checkout.session.completed) sans signature.
      Stripe::CompletedCheckoutService.new(payment: payment).run!(
        stripe_checkout_session_id: "cs_test_123",
        stripe_payment_intent_id: "pi_test_123"
      )

      expect(payment.reload.status).to eq("paid")
      expect(stay.reload.status).to eq("confirmed")
    end
  end
end
