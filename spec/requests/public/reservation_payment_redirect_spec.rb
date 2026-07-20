require "rails_helper"

# Bug « le clic final ne fait rien » (2026-07-20) — deux causes distinctes :
#
# 1. Le formulaire de l'étape coordonnées postait via Turbo alors que la réponse
#    est un redirect vers Stripe Checkout (hôte externe) : le fetch Turbo suit le
#    redirect, CORS le bloque, aucune navigation. Le formulaire doit porter
#    data-turbo="false" pour un POST natif.
# 2. Si Stripe échoue APRÈS création du séjour, le fallback redirigeait vers
#    `builder.booking.token` — or un séjour sans hébergement classique (camping,
#    espaces seuls) n'a PAS de Booking (stay-first, epic #26) → NoMethodError 500,
#    alors que le Stay et l'email de confirmation existaient déjà.
RSpec.describe "Public::Reservations — redirection paiement (étape finale)", type: :request do
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
    it "désactive Turbo (le redirect Stripe est cross-origin, insuivable en fetch)" do
      get "/reservation/coordonnees"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-turbo="false"')
    end
  end

  describe "échec Stripe après création du séjour" do
    before do
      allow(StripeService.instance).to receive(:create_checkout_session)
        .and_raise(Stripe::AuthenticationError.new("Invalid API Key provided"))
    end

    it "séjour camping seul (sans Booking) : redirige vers la page séjour, pas de 500" do
      expect {
        post "/reservation/coordonnees", params: {
          reservation: base_contact.merge(campings: [{ kind: "tente", people: 2, nights: 2 }])
        }
      }.to change(Stay, :count).by(1)

      stay = Stay.last
      expect(stay.bookables.grep(Booking)).to be_empty # pas de Booking : le fallback ne peut pas s'appuyer dessus
      expect(response).to redirect_to("/sejour/#{stay.token}")
      expect(flash[:notice]).to include("Nous vous recontactons")
    end

    it "séjour avec hébergement : même cible stay-first (/sejour/:token)" do
      post "/reservation/coordonnees", params: {
        reservation: base_contact.merge(lodging_id: hulotte.id)
      }

      stay = Stay.last
      expect(response).to redirect_to("/sejour/#{stay.token}")
    end

    it "la page séjour du fallback se rend (le client atterrit sur du concret)" do
      post "/reservation/coordonnees", params: {
        reservation: base_contact.merge(campings: [{ kind: "tente", people: 2, nights: 2 }])
      }
      follow_redirect!

      expect(response).to have_http_status(:ok)
    end
  end
end
