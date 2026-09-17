require "rails_helper"

# Epic #260, phase 2, décision 6 — les draps au funnel public : un bloc
# « Options » à l'étape Composition, deux compteurs, une ligne de devis par type
# de lit, et la mention « brouette de bûches incluse » sur les gîtes qui ont un
# poêle. Le tout facturé par LIT, jamais par nuit.
RSpec.describe "Funnel — options draps et bûches (epic #260, phase 2)", type: :request do
  let!(:cheveche) do
    lodging = Lodging.create!(name: "La Chevêche", price_night_cents: 27_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  # Lundi → vendredi : que des nuits de semaine, donc jamais le refus de la nuit
  # de week-end isolée (phase 1). Un lundi fixe, pour ne pas dépendre du jour.
  let(:arrival) { Date.new(2026, 10, 5) }
  let(:nights)  { 4 }

  def start_funnel
    post "/reservation/sejour", params: {
      reservation: { arrival_date: arrival.iso8601,
                     departure_date: (arrival + nights).iso8601, adults: 2 }
    }
  end

  it "s'appuie sur un lundi" do
    expect(arrival.wday).to eq(1)
  end

  describe "l'étape Composition" do
    before { start_funnel }

    it "propose les deux compteurs de draps avec leur tarif" do
      get "/reservation/composer"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Draps pour lit simple")
      expect(response.body).to include("Draps pour lit double")
      expect(response.body).to include("reservation[linen_single]")
      expect(response.body).to include("reservation[linen_double]")
    end

    it "annonce la brouette de bûches sur La Chevêche, pas sur La Hulotte" do
      get "/reservation/composer"

      expect(response.body).to include("Brouette de bûches incluse")
      # Une seule mention par écran de carte + grille pour le seul gîte concerné :
      # La Hulotte n'a pas de poêle, elle ne doit rien annoncer.
      expect(response.body.scan("Brouette de bûches incluse").size).to eq(2)
    end
  end

  describe "le devis live" do
    before { start_funnel }

    it "ajoute une ligne par type de lit, au tarif du site" do
      post "/reservation/devis", params: {
        reservation: { lodging_night_ids: Array.new(nights) { cheveche.id.to_s },
                       linen_single: "2", linen_double: "1" }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Draps pour lit simple × 2")
      expect(response.body).to include("Draps pour lit double × 1")
    end

    it "facture les draps une seule fois, quelle que soit la durée" do
      post "/reservation/devis", params: {
        reservation: { lodging_night_ids: Array.new(nights) { cheveche.id.to_s },
                       linen_single: "1" }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      long = response.body

      post "/reservation/sejour", params: {
        reservation: { arrival_date: arrival.iso8601,
                       departure_date: (arrival + 1).iso8601, adults: 2 }
      }
      post "/reservation/devis", params: {
        reservation: { lodging_night_ids: [cheveche.id.to_s], linen_single: "1" }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(long).to include("Draps pour lit simple × 1")
      expect(response.body).to include("Draps pour lit simple × 1")
    end
  end

  describe "la soumission" do
    before { start_funnel }

    it "persiste les draps sur le séjour sans gonfler le total" do
      expect {
        post "/reservation/coordonnees", params: {
          reservation: {
            arrival_date: arrival.iso8601, departure_date: (arrival + nights).iso8601,
            dogs_count: 0, first_name: "Camille", last_name: "Martin",
            email: "camille-draps@example.com", phone: "+32470000000",
            lodging_night_ids: Array.new(nights) { cheveche.id.to_s },
            linen_single: "2", linen_double: "1"
          }
        }
      }.to change(Stay, :count).by(1)

      stay = Stay.last
      expect(stay.linen_orders.sum(&:price_cents)).to eq(4_000)

      ventilated = stay.bookables.sum { |b| b.try(:price_cents).to_i } +
                   stay.linen_orders.sum(&:price_cents)
      expect(ventilated).to eq(stay.total_amount_cents)
    end

    it "montre les draps et les bûches sur la page client" do
      post "/reservation/coordonnees", params: {
        reservation: {
          arrival_date: arrival.iso8601, departure_date: (arrival + nights).iso8601,
          dogs_count: 0, first_name: "Camille", last_name: "Martin",
          email: "camille-draps2@example.com", phone: "+32470000000",
          lodging_night_ids: Array.new(nights) { cheveche.id.to_s },
          linen_single: "2"
        }
      }
      stay = Stay.last

      get "/sejour/#{stay.token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Draps pour lit simple × 2")
      expect(response.body).to include("Brouette de bûches incluse")
    end
  end
end
