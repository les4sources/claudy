require "rails_helper"

# Epic #234, phase 2 — le devis doit MONTRER le forfait, pas seulement l'appliquer :
# une ligne par forfait avec sa plage de dates, en admin comme au funnel public
# (décision 7 : même moteur des deux côtés).
RSpec.describe "Devis — forfaits multi-jours des salles (epic #234, phase 2)", type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end
  let!(:petite_salle) { Space.create!(name: "Petite Salle", code: "SAU", capacity: 1) }

  let(:lundi)    { (Date.today + 60).next_occurring(:monday) }
  let(:vendredi) { lundi + 4 }
  let(:cinq_journees) { %w[journee journee journee journee journee] }

  describe "rail de prix admin" do
    let(:user) { User.create!(email: "admin-forfaits@les4sources.be", password: "password123") }
    before { sign_in user }

    it "affiche « forfait 5 jours » et 525 € pour la Petite Salle du lundi au vendredi" do
      post quote_stays_path,
           params: {
             stay: {
               customer_mode: "new",
               new_customer: { first_name: "Groupe", last_name: "Semaine",
                               email: "groupe@example.com", phone: "0470111222" },
               arrival_date: lundi.iso8601, departure_date: vendredi.iso8601,
               adults: 8, children: 0, dogs_count: 0, lodging_id: "",
               space_slots: { petite_salle: cinq_journees }
             }
           },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("forfait 5 jours")
      expect(response.body).to include("525")
    end
  end

  describe "récapitulatif du funnel public" do
    before do
      allow(StripeService.instance).to receive(:create_checkout_session)
        .and_return(OpenStruct.new(url: "https://checkout.stripe.test/session/x"))
    end

    it "affiche « forfait 5 jours » dans le devis live" do
      post "/reservation/sejour", params: {
        reservation: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601, adults: 8 }
      }

      post public_reservation_quote_path,
           params: { reservation: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601,
                                    adults: 8, space_slots: { petite_salle: cinq_journees } } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("forfait 5 jours")
      expect(response.body).to include("525")
    end
  end
end
