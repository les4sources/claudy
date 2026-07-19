require "rails_helper"

# Epic #81, Phase 7 — Saisie rapide datée depuis le calendrier + duplication.
#
# A. Le form NEW lit `date`/`space`/`duplicate_from` et se préremplit :
#    - `date`               → arrivée = date, départ = date + 1 (hébergement) ;
#    - `date` + `space=1`   → une ligne d'espace datée, SANS dates de séjour ;
#    - `duplicate_from`     → client + composition du séjour source, dates VIDES.
# B. La modale du calendrier expose un bouton « Dupliquer » vers ce form.
RSpec.describe "Stays — saisie rapide datée & duplication (epic #81, Phase 7)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-quick-create@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging)      { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }
  let(:date)          { Date.today + 30 }

  describe "GET /stays/new?date=… — préremplissage hébergement" do
    it "préremplit l'arrivée à la date et le départ au lendemain (1 nuit)" do
      get new_stay_path(date: date.iso8601)
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/name="stay\[arrival_date\]"[^>]*value="#{date.iso8601}"/)
      expect(response.body).to match(/name="stay\[departure_date\]"[^>]*value="#{(date + 1).iso8601}"/)
    end
  end

  describe "GET /stays/new?date=…&space=1 — préremplissage espace daté" do
    it "ouvre une ligne d'espace datée, SANS dates de séjour" do
      get new_stay_path(date: date.iso8601, space: 1)
      expect(response).to have_http_status(:ok)
      # Une ligne d'espace porte la date cliquée.
      expect(response.body).to match(/name="stay\[halls\]\[0\]\[date\]"[^>]*value="#{date.iso8601}"/)
      # Aucune date de séjour (journée sèche : l'admin ne saisit pas de nuitée).
      expect(response.body).not_to match(/name="stay\[arrival_date\]"[^>]*value="\d/)
      expect(response.body).not_to match(/name="stay\[departure_date\]"[^>]*value="\d/)
    end
  end

  describe "GET /stays/new?duplicate_from=… — préremplissage par duplication" do
    let!(:source) do
      draft = Reservations::Draft.new(
        lodging_id:     lodging.id,
        arrival_date:   date,
        departure_date: date + 2,
        adults:         2,
        dogs_count:     0,
        first_name:     "Alice",
        last_name:      "Martin",
        email:          "alice@example.com",
        phone:          "0470111222",
        halls:          [{ kind: "grande_salle", date: date.iso8601, period: "journee" }],
        meals:          [{ kind: "buffet", date: date.iso8601, people: 3 }]
      )
      builder = Reservations::Builder.new(draft: draft, admin: true, source: "manual", price_override_cents: 88_800)
      builder.run!
      builder.stay
    end

    it "reprend le client et la composition, mais laisse les dates vides" do
      get new_stay_path(duplicate_from: source.id)
      expect(response).to have_http_status(:ok)

      # Client conservé (nom pré-rempli dans le panneau « nouveau client » de repli).
      expect(response.body).to include('value="Alice"')
      expect(response.body).to include('value="Martin"')
      # …et surtout PRÉSÉLECTIONNÉ dans le <select> « Client existant » (passe
      # navigateur Phase 7) : sans ça, la soumission partait en mode « existant »
      # avec customer_id vide.
      expect(response.body).to match(/name="stay\[customer_id\]".*?<option selected[^>]*value="#{source.customer_id}"/m)
      # Composition conservée : hébergement présélectionné + une ligne d'espace.
      expect(response.body).to match(/selected="selected" value="#{lodging.id}"/)
      expect(response.body).to match(/selected="selected" value="grande_salle"/)

      # Dates de séjour VIDES (un clone aux mêmes dates surbookerait).
      expect(response.body).not_to match(/name="stay\[arrival_date\]"[^>]*value="\d/)
      expect(response.body).not_to match(/name="stay\[departure_date\]"[^>]*value="\d/)
      # Prix imposé NON copié (champ vide malgré l'override du séjour source).
      expect(response.body).not_to match(/name="stay\[price_override\]"[^>]*value="\d/)
    end
  end

  describe "modale séjour — bouton Dupliquer" do
    let!(:stay) do
      draft = Reservations::Draft.new(
        lodging_id: lodging.id, arrival_date: date, departure_date: date + 1,
        adults: 2, dogs_count: 0,
        first_name: "Bob", last_name: "Durand", email: "bob@example.com", phone: "0470999888"
      )
      builder = Reservations::Builder.new(draft: draft, admin: true, source: "manual")
      builder.run!
      builder.stay
    end

    it "affiche un lien Dupliquer vers le form NEW prérempli" do
      get stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(new_stay_path(duplicate_from: stay.id))
      expect(response.body).to include("Dupliquer")
    end
  end
end
