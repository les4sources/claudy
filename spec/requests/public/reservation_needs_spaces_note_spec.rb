require "rails_helper"

# Améliorations UX funnel /reservation :
#   feature 4 — textarea « précisez votre besoin » sous les espaces → note interne
#               du SpaceBooking, visible dans la modale admin ;
#   feature 5 — cards de besoins à l'étape 1 + masquage/affichage des blocs à
#               l'étape 2, comportement conservateur (rien coché → tout visible).
RSpec.describe "Public::Reservations — needs & spaces_note", type: :request do
  include ActiveJob::TestHelper

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end
  let!(:grande_salle) { Space.create!(name: "Grande Salle", code: "TIL", capacity: 1) }

  let(:arrival)   { (Date.today + 60).iso8601 }
  let(:departure) { (Date.today + 62).iso8601 }

  before do
    allow(StripeService.instance).to receive(:create_checkout_session)
      .and_return(OpenStruct.new(url: "https://checkout.stripe.test/session/x"))
  end

  describe "étape 1 — cards de besoins (feature 5)" do
    it "affiche les 6 cards cochables" do
      get "/reservation/sejour"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="reservation[needs][]"')
      ["Gîte pour groupe", "Salles et cuisine pro", "Espace camping",
       "Espace van", "Repas", "Activités"].each do |label|
        expect(response.body).to include(label)
      end
    end
  end

  describe "étape 2 — transmission des needs au contrôleur JS de masquage" do
    it "sans sélection : selected-value vide (conservateur, tout visible)" do
      post "/reservation/sejour", params: { reservation: { arrival_date: arrival, departure_date: departure, adults: 2 } }
      get "/reservation/composer"

      expect(response.body).to include('data-public--needs-selected-value="[]"')
      # Les blocs restent tous présents (le masquage est purement client-side).
      expect(response.body).to include('data-needs-block')
    end

    it "avec sélection : la sélection est transmise et survit à l'aller-retour" do
      post "/reservation/sejour", params: {
        reservation: { arrival_date: arrival, departure_date: departure, adults: 2, needs: %w[gite salles] }
      }
      get "/reservation/composer"

      expect(response.body).to include("gite").and include("salles")
      expect(response.body).to include('data-public--needs-selected-value=')
      # Le bloc espaces (salles) et l'hébergement (gite) portent leurs tokens.
      expect(response.body).to include('data-needs-block="salles"')
      expect(response.body).to include('data-needs-block="gite"')
      # La zone « Ajouter » et ses boutons de redéploiement existent.
      expect(response.body).to include('data-needs-add-token=')
    end
  end

  describe "feature 4 — textarea espaces → note interne du SpaceBooking" do
    it "range la précision dans la note interne, visible côté admin" do
      note = "Arrivée vendredi 17h, besoin de 60 chaises"

      perform_enqueued_jobs do
        post "/reservation/coordonnees", params: {
          reservation: {
            arrival_date: arrival, departure_date: departure,
            dogs_count: 0, first_name: "Espace", last_name: "Test",
            email: "espace@example.com", phone: "+32470111222",
            space_slots: { grande_salle: ["journee", ""] },
            spaces_note: note
          }
        }
      end

      stay = Stay.last
      sb = stay.stay_items.map(&:bookable).grep(SpaceBooking).first
      expect(sb).to be_present
      expect(sb.notes).to eq("Demande client espaces : #{note}")

      # Agrégée dans la modale admin (source « Espaces »).
      entries = stay.decorate.internal_notes_entries
      expect(entries.map { |e| e[:text] }).to include("Demande client espaces : #{note}")

      # Round-trip édition : le DraftReconstructor rend le texte BRUT (sans préfixe).
      rebuilt = Stays::DraftReconstructor.call(stay)
      expect(rebuilt.spaces_note).to eq(note)
    end

    it "pas de précision → aucune note client sur le SpaceBooking" do
      perform_enqueued_jobs do
        post "/reservation/coordonnees", params: {
          reservation: {
            arrival_date: arrival, departure_date: departure,
            dogs_count: 0, first_name: "Sans", last_name: "Note",
            email: "sans@example.com", phone: "+32470111333",
            space_slots: { grande_salle: ["journee", ""] }
          }
        }
      end

      sb = Stay.last.stay_items.map(&:bookable).grep(SpaceBooking).first
      expect(sb.notes).to be_blank
    end
  end
end
