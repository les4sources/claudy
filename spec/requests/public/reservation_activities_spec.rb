require "rails_helper"

# Epic #55, Phase 4 — étape « Activités » du funnel public /reservation, insérée
# entre la composition et les coordonnées. L'utilisateur choisit un CRÉNEAU daté
# (ExperienceAvailability) dans la fenêtre [arrivée, départ] de son séjour — jour
# du départ COMPRIS depuis la décision du 2026-08-21 ; la
# sélection survit en session jusqu'au commit, où elle devient un
# ExperienceBooking `pending` rattaché au Stay.
RSpec.describe "Public::Reservations — étape activités (/reservation/activites)", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  # Fenêtre du séjour : [today+40, today+43] → les trois nuits plus la matinée
  # de départ.
  let(:arrival)   { Date.today + 40 }
  let(:departure) { Date.today + 43 }

  let!(:experience)       { Experience.create!(name: "Balade avec les ânes", fixed_price_cents: 2_000, price_cents: 1_000, max_participants: 8) }
  let!(:other_experience) { Experience.create!(name: "Atelier forge", price_cents: 4_000) }
  let!(:after_experience) { Experience.create!(name: "Cueillette tardive", price_cents: 3_000) }

  # Créneau DANS la fenêtre (jour intermédiaire).
  let!(:slot_in)  { ExperienceAvailability.create!(experience: experience, available_on: arrival + 1, starts_at: "10:00", max_participants: 8) }
  # Créneau le JOUR DU DÉPART : proposé (une activité en matinée avant de charger
  # la voiture se vend — décision Michael 2026-08-21).
  let!(:slot_departure) { ExperienceAvailability.create!(experience: other_experience, available_on: departure, starts_at: "10:00") }
  # Créneau HORS fenêtre pour de bon : le lendemain du départ.
  let!(:slot_out) { ExperienceAvailability.create!(experience: after_experience, available_on: departure + 1, starts_at: "10:00") }

  # Amorce le draft en session avec les dates du séjour (étape 1).
  def seed_dates
    post "/reservation/sejour", params: { reservation: { arrival_date: arrival.iso8601, departure_date: departure.iso8601, adults: 2 } }
  end

  describe "GET /reservation/activites (affichage selon la fenêtre)" do
    it "affiche l'étape et les activités ayant un créneau dans la fenêtre" do
      seed_dates
      get "/reservation/activites"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Balade avec les ânes")
      # Le créneau dans la fenêtre est proposé (champ availability_id caché).
      expect(response.body).to include('name="reservation[experiences][0][availability_id]"')
    end

    it "propose aussi les créneaux du JOUR DU DÉPART" do
      seed_dates
      get "/reservation/activites"

      expect(response.body).to include("Atelier forge")
    end

    it "n'affiche PAS un créneau postérieur au départ" do
      seed_dates
      get "/reservation/activites"

      expect(response.body).not_to include("Cueillette tardive")
    end
  end

  describe "GET /reservation/activites — aucun créneau dans la fenêtre" do
    before { slot_in.destroy && slot_departure.destroy && slot_out.destroy }

    it "reste franchissable et l'indique clairement" do
      seed_dates
      get "/reservation/activites"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aucune activité")
      # Un chemin de sortie vers les coordonnées reste offert.
      expect(response.body).to include(public_reservation_contact_path)
    end
  end

  describe "la sélection de créneau survit jusqu'au commit" do
    before do
      allow(StripeService.instance).to receive(:create_checkout_session)
        .and_return(OpenStruct.new(url: "https://checkout.stripe.test/session/act"))
    end

    it "persiste le créneau puis crée un ExperienceBooking pending rattaché au Stay" do
      seed_dates

      # Étape activités : on choisit le créneau dans la fenêtre.
      post "/reservation/activites", params: {
        reservation: { experiences: { "0" => { id: experience.id, availability_id: slot_in.id, participants: "4" } } }
      }
      expect(response).to redirect_to("/reservation/coordonnees")

      # Commit final : les coordonnées ne re-portent PAS les activités — c'est le
      # draft en session qui les conserve d'une étape à l'autre.
      expect {
        post "/reservation/coordonnees", params: {
          reservation: {
            lodging_id: hulotte.id, arrival_date: arrival.iso8601, departure_date: departure.iso8601,
            dogs_count: 0, first_name: "Nina", last_name: "Test",
            email: "nina@example.com", phone: "+32470111222"
          }
        }
      }.to change(ExperienceBooking, :count).by(1)

      eb = ExperienceBooking.last
      expect(eb).to be_pending
      expect(eb.experience_availability).to eq(slot_in)
      expect(eb.participants).to eq(4)
      expect(eb.stay).to eq(Stay.last)
    end
  end
  # Décision Michael 2026-08-21 : la capacité borne le canal CLIENT. Le refus
  # doit tomber ICI, où le visiteur peut encore corriger — pas au commit, où
  # l'activité serait écartée en silence après le paiement de l'acompte.
  describe "POST /reservation/activites — capacité du créneau" do
    let(:autre_stay) { Stay.create!(customer: Customer.create!(email: "voisin@example.com", customer_type: "individual")) }

    before do
      # 8 places au total, 6 déjà prises : il en reste 2.
      ExperienceBooking.create!(experience_availability: slot_in, stay: autre_stay, participants: 6, status: "pending")
      seed_dates
    end

    def choose(participants)
      post "/reservation/activites", params: {
        reservation: { experiences: { "0" => { id: experience.id, availability_id: slot_in.id, participants: participants } } }
      }
    end

    it "laisse passer une demande qui tient dans les places restantes" do
      choose(2)

      expect(response).to redirect_to("/reservation/coordonnees")
    end

    it "arrête le visiteur, sans le faire avancer, quand il en demande trop" do
      choose(3)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Il ne reste plus assez de places")
      expect(response.body).to include("2 places restantes")
    end

    it "n'annonce que les places encore libres dans le champ de saisie" do
      get "/reservation/activites"

      expect(response.body).to include("2 places restantes")
      expect(response.body).to include('max="2"')
    end
  end
end
