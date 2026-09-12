require "rails_helper"

# Epic #260, phase 1, décision 3 — hors du 15 novembre au 14 mars, le funnel
# public REFUSE une nuit de vendredi ou de samedi isolée.
#
# Le bug tel qu'il a été constaté au navigateur le 2026-09-08 : vendredi 16 →
# samedi 17 octobre 2026, La Chevêche, devis 275 €. Le site ne vend cette nuit
# seule qu'en saison basse, et le funnel l'annonçait déjà en toutes lettres —
# mais rien ne refusait côté serveur.
RSpec.describe "Funnel — la nuit de week-end seule (epic #260)", type: :request do
  let!(:cheveche) do
    lodging = Lodging.create!(name: "La Chevêche", price_night_cents: 27_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  # Octobre 2026 = HAUTE saison ; janvier 2027 = saison basse.
  let(:vendredi_octobre) { Date.new(2026, 10, 16) }
  let(:vendredi_janvier) { Date.new(2027, 1, 15) }

  before do
    allow(StripeService.instance).to receive(:create_checkout_session)
      .and_return(OpenStruct.new(url: "https://checkout.stripe.test/x"))
  end

  def compose(arrival, nights)
    post "/reservation/sejour", params: {
      reservation: { arrival_date: arrival.iso8601, departure_date: (arrival + nights).iso8601, adults: 2 }
    }
    post "/reservation/devis", params: {
      reservation: { lodging_night_ids: Array.new(nights) { cheveche.id.to_s } }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  def submit(arrival, nights)
    post "/reservation/coordonnees", params: {
      reservation: {
        arrival_date: arrival.iso8601, departure_date: (arrival + nights).iso8601,
        dogs_count: 0, first_name: "Camille", last_name: "Martin",
        email: "camille-weekend@example.com", phone: "+32470000000",
        lodging_night_ids: Array.new(nights) { cheveche.id.to_s }
      }
    }
  end

  it "s'appuie sur des dates justes" do
    expect(vendredi_octobre.wday).to eq(5)
    expect(vendredi_janvier.wday).to eq(5)
  end

  describe "en haute saison" do
    it "refuse la demande et explique quelle nuit ajouter" do
      expect { submit(vendredi_octobre, 1) }.not_to change(Stay, :count)

      expect(response.body).to include("2 nuits minimum")
      expect(response.body).to include("Ajoutez la nuit du")
      expect(response.body).to include("samedi 17 octobre 2026")
    end

    it "bloque le bouton « Continuer » du devis live, avec la raison écrite" do
      compose(vendredi_octobre, 1)

      expect(response.body).to include("2 nuits minimum")
      expect(response.body).to match(/<button[^>]*disabled/)
    end

    it "laisse passer la paire vendredi + samedi" do
      compose(vendredi_octobre, 2)

      expect(response.body).not_to include("2 nuits minimum")
      expect { submit(vendredi_octobre, 2) }.to change(Stay, :count).by(1)
      # Forfait week-end de La Chevêche : 480 €, pas 2 × 260.
      expect(Stay.order(:created_at).last.total_amount_cents).to eq(48_000)
    end

    it "refuse aussi un jeudi → samedi (le vendredi reste orphelin)" do
      jeudi = vendredi_octobre - 1

      expect { submit(jeudi, 2) }.not_to change(Stay, :count)
      expect(response.body).to include("Ajoutez la nuit du")
    end
  end

  describe "en saison basse" do
    it "accepte la nuit du vendredi seule et la facture 260 €" do
      expect { submit(vendredi_janvier, 1) }.to change(Stay, :count).by(1)

      expect(Stay.order(:created_at).last.total_amount_cents).to eq(26_000)
    end
  end
end
