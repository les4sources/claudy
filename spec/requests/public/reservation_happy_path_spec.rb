require "rails_helper"

# AC-T2-28 — parcours happy-path B2C de bout en bout (dates → composition →
# coordonnées → paiement Stripe test mode → Stay pending en attente de Malau).
RSpec.describe "Parcours /reservation complet (happy-path B2C)", type: :request do
  include ActiveJob::TestHelper

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  let(:arrival) { (Date.today + 60).iso8601 }
  let(:departure) { (Date.today + 63).iso8601 }

  before do
    allow(StripeService.instance).to receive(:create_checkout_session)
      .and_return(OpenStruct.new(url: "https://checkout.stripe.test/session/happy"))
  end

  it "déroule entrée → devis → coordonnées → Stay pending + email (sans Stripe, issue #215)" do
    get "/reservation"
    expect(response).to redirect_to("/reservation/sejour")

    post "/reservation/devis",
         params: { reservation: { lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure, meals: { "0" => { kind: "repas", people: "4" } } } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("Total TVAC")

    get "/reservation/coordonnees"
    expect(response).to have_http_status(:ok)

    perform_enqueued_jobs do
      expect {
        post "/reservation/coordonnees", params: {
          reservation: {
            lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure,
            dogs_count: 1, first_name: "Happy", last_name: "Path",
            email: "happy@example.com", phone: "+32470999888",
            meals: { "0" => { kind: "repas", people: "4" } }
          }
        }
      }.to change(Stay, :count).by(1)
    end

    stay = Stay.last
    # Issue #215 : le funnel n'encaisse plus rien — il enregistre une demande et
    # renvoie le client sur sa page de séjour. L'acompte viendra de la
    # pré-confirmation du Pôle Accueil.
    expect(response).to redirect_to("/sejour/#{stay.token}")
    expect(stay.status).to eq("pending")        # PAS d'auto-confirm (Q5)
    expect(stay.source).to eq("reservation")    # canal (Q9)
    expect(stay.customer.email).to eq("happy@example.com")
    expect(stay.stay_items.count).to eq(1)
    # Hulotte 3 nuits (485 + 2×260 = 1005) + repas (4×15 = 60) + chien 50 = 1115 €
    expect(stay.total_amount_cents).to eq(111_500)
    expect(stay.payments).to be_empty
  end
end
