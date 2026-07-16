require "rails_helper"

# Epic #55, Phase 4 — étape « Activités » du funnel public /reservation, insérée
# entre la composition et les coordonnées. L'utilisateur choisit un CRÉNEAU daté
# (ExperienceAvailability) dans la fenêtre [arrivée, départ) de son séjour ; la
# sélection survit en session jusqu'au commit, où elle devient un
# ExperienceBooking `pending` rattaché au Stay.
RSpec.describe "Public::Reservations — étape activités (/reservation/activites)", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  # Fenêtre du séjour : [today+40, today+43) → nuits 40, 41, 42.
  let(:arrival)   { Date.today + 40 }
  let(:departure) { Date.today + 43 }

  let!(:experience)       { Experience.create!(name: "Balade avec les ânes", fixed_price_cents: 2_000, price_cents: 1_000, max_participants: 8) }
  let!(:other_experience) { Experience.create!(name: "Atelier forge", price_cents: 4_000) }

  # Créneau DANS la fenêtre (jour intermédiaire).
  let!(:slot_in)  { ExperienceAvailability.create!(experience: experience, available_on: arrival + 1, starts_at: "10:00", max_participants: 8) }
  # Créneau HORS fenêtre : le jour du départ est exclu ([arrivée, départ)).
  let!(:slot_out) { ExperienceAvailability.create!(experience: other_experience, available_on: departure, starts_at: "10:00") }

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

    it "n'affiche PAS un créneau hors fenêtre (jour du départ exclu)" do
      seed_dates
      get "/reservation/activites"

      expect(response.body).not_to include("Atelier forge")
    end
  end

  describe "GET /reservation/activites — aucun créneau dans la fenêtre" do
    before { slot_in.destroy && slot_out.destroy }

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
end
