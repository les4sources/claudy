require "rails_helper"

# Issue #215 — inversion de l'ordre du funnel B2C. L'étape finale n'encaisse
# plus rien : elle enregistre une DEMANDE. Le client ne voit plus Stripe à ce
# moment-là, et aucun Payment n'existe tant que le Pôle Accueil n'a pas
# pré-confirmé. Ce fichier remplace `reservation_payment_redirect_spec.rb`, qui
# verrouillait le redirect Stripe désormais supprimé — mais il en garde le cas
# limite qui avait coûté un 500 : le séjour SANS Booking (camping / espaces
# seuls), sur lequel toute cible de redirection tirée du booking explose.
RSpec.describe "Public::Reservations — soumission de l'étape finale", type: :request do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival) { (Date.today + 40).iso8601 }
  let(:departure) { (Date.today + 42).iso8601 }

  let(:base_contact) do
    {
      arrival_date: arrival, departure_date: departure, dogs_count: 0,
      adults: 2, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470000000"
    }
  end

  describe "formulaire de l'étape coordonnées" do
    it "n'annonce plus un paiement, mais l'envoi d'une demande" do
      get "/reservation/coordonnees"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Envoyer ma demande de réservation")
      expect(response.body).not_to match(/payer l'acompte/i)
      expect(response.body).to include("Pôle Accueil")
      expect(response.body).to match(/Rien n'est prélevé aujourd'hui/i)
      expect(response.body).not_to match(/Paiement sécurisé par Stripe/i)
    end
  end

  describe "POST /reservation/coordonnees" do
    it "crée un séjour pending SANS aucun Payment ni appel Stripe" do
      expect(StripeService.instance).not_to receive(:create_checkout_session)

      expect {
        post "/reservation/coordonnees", params: {
          reservation: base_contact.merge(lodging_id: hulotte.id)
        }
      }.to change(Stay, :count).by(1).and change(Payment, :count).by(0)

      expect(Stay.last.status).to eq("pending")
    end

    it "redirige vers la page séjour, jamais vers Stripe Checkout" do
      post "/reservation/coordonnees", params: {
        reservation: base_contact.merge(lodging_id: hulotte.id)
      }

      stay = Stay.last
      expect(response).to redirect_to("/sejour/#{stay.token}")
      expect(response.location).not_to include("checkout.stripe.com")
      expect(flash[:notice]).to include("Pôle Accueil")
    end

    it "séjour camping seul (sans Booking) : même cible, pas de 500" do
      expect {
        post "/reservation/coordonnees", params: {
          reservation: base_contact.merge(campings: [{ kind: "tente", people: 2, nights: 2 }])
        }
      }.to change(Stay, :count).by(1)

      stay = Stay.last
      expect(stay.bookables.grep(Booking)).to be_empty
      expect(response).to redirect_to("/sejour/#{stay.token}")
    end

    it "la page séjour d'arrivée se rend (le client atterrit sur du concret)" do
      post "/reservation/coordonnees", params: {
        reservation: base_contact.merge(campings: [{ kind: "tente", people: 2, nights: 2 }])
      }
      follow_redirect!

      expect(response).to have_http_status(:ok)
    end

    it "envoie l'accusé de réception, sans montant d'acompte", queue_adapter: :test do
      expect {
        post "/reservation/coordonnees", params: {
          reservation: base_contact.merge(lodging_id: hulotte.id)
        }
      }.to have_enqueued_mail(ReservationMailer, :confirmation_request)
    end
  end
end
