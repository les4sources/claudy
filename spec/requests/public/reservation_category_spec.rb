require "rails_helper"

# Catégorie de séjour dans le funnel public (Michael 2026-07-21) : champ « Type de
# séjour » à l'étape coordonnées, optionnel, SANS la catégorie interne
# « Les 4 Sources ». La valeur survit jusqu'au Stay créé.
RSpec.describe "Funnel /reservation — type de séjour (catégorie)", type: :request do
  include ActiveJob::TestHelper

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  let(:arrival)   { (Date.today + 60).iso8601 }
  let(:departure) { (Date.today + 63).iso8601 }

  before do
    allow(StripeService.instance).to receive(:create_checkout_session)
      .and_return(OpenStruct.new(url: "https://checkout.stripe.test/session/cat"))
  end

  def compose!
    post "/reservation/devis",
         params: { reservation: { lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  describe "étape coordonnées" do
    it "affiche le champ Type de séjour SANS l'option interne « Les 4 Sources »" do
      compose!
      get "/reservation/coordonnees"
      expect(response.body).to include("reservation[category]")
      expect(response.body).to include("Type de séjour")
      expect(response.body).to include("Mariage")
      # La catégorie interne ne doit JAMAIS être une option du select public
      # (« Les 4 Sources » figure ailleurs dans la page — branding —, on cible
      # donc précisément la valeur d'option).
      expect(response.body).not_to include('value="les4sources"')
    end
  end

  describe "commit" do
    it "porte la catégorie choisie jusqu'au Stay créé" do
      compose!
      expect {
        post "/reservation/coordonnees", params: {
          reservation: {
            lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure,
            first_name: "Cat", last_name: "Egory", email: "cat-funnel@example.com",
            phone: "+32470999888", category: "friends"
          }
        }
      }.to change(Stay, :count).by(1)

      expect(Stay.last.category).to eq("friends")
    end

    it "neutralise une catégorie interne forgée (les4sources) venue du public" do
      compose!
      post "/reservation/coordonnees", params: {
        reservation: {
          lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure,
          first_name: "Cat", last_name: "Egory", email: "cat-forge@example.com",
          phone: "+32470999888", category: "les4sources"
        }
      }
      expect(Stay.last.category).to be_nil
    end
  end
end
