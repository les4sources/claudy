require "rails_helper"

# Epic #66, Phase 5 — La modale séjour (stays#show, rendue sans layout et injectée
# par le contrôleur Stimulus stay-details) affiche la COMPOSITION COMPLÈTE du
# séjour : hébergement + espaces + camping + van + repas + activités, avec un lien
# d'édition vers le form Phase 1. La gestion d'activités (epic #55, Phase 6) reste
# fonctionnelle (turbo-frame d'ancrage + formulaire d'ajout inchangés).
RSpec.describe "Stays#show — composition complète (epic #66, Phase 5)", type: :request do
  include Devise::Test::IntegrationHelpers

  # Staff/accueil sans `human` = admin global (voit toutes les activités).
  let(:admin)    { User.create!(email: "staff-compo@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(email: "compo@example.com", customer_type: "individual", first_name: "Ada", last_name: "Lovelace") }
  let(:lodging)  { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:space)    { Space.create!(name: "Grande Salle", capacity: 40) }

  let(:from) { Date.today + 30 }
  let(:to)   { Date.today + 32 }

  # Un séjour multi-éléments : hébergement + espace + camping + van + repas + activité.
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: from, departure_date: to, total_amount_cents: 100_000)
  end

  let(:porteur) { Human.create!(name: "Porteuse", email: "porteuse@example.com") }
  let(:experience) { Experience.create!(name: "Balade ânes", human: porteur, fixed_price_cents: 4000, price_cents: 1500) }
  let(:availability) { ExperienceAvailability.create!(experience: experience, available_on: from + 1, starts_at: "10:00") }

  before do
    booking = Booking.create!(firstname: "Ada", lastname: "Lovelace", group_name: "Les Analytiques",
                              lodging: lodging, from_date: from, to_date: to,
                              adults: 3, children: 1, status: "confirmed", booking_type: "lodging",
                              price_cents: 97_000)
    stay.stay_items.create!(bookable: booking)

    space_booking = SpaceBooking.create!(firstname: "Ada", group_name: "Les Analytiques",
                                         from_date: from, to_date: from, status: "confirmed", price_cents: 12_000)
    SpaceReservation.create!(space: space, space_booking: space_booking, date: from)
    stay.stay_items.create!(bookable: space_booking)

    camping = CampingBooking.create!(firstname: "Ada", group_name: "Les Analytiques",
                                     from_date: from, to_date: to, people: 5, kind: "tente",
                                     status: "confirmed", price_cents: 9_000)
    stay.stay_items.create!(bookable: camping)

    van = VanBooking.create!(firstname: "Ada", group_name: "Les Analytiques",
                             from_date: from, to_date: to, vehicles: 2, status: "confirmed", price_cents: 6_000)
    stay.stay_items.create!(bookable: van)

    MealOrder.create!(stay: stay, kind: "buffet", date: from + 1, people: 8, price_cents: 8_000)

    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 4, status: "confirmed")

    sign_in admin
  end

  describe "GET /stays/:id" do
    before { get stay_path(stay) }

    it "répond OK et affiche l'en-tête du séjour" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Séjour ##{stay.id}")
    end

    it "liste la section HÉBERGEMENT (lodging, dates, occupants)" do
      expect(response.body).to include("Hébergement")
      expect(response.body).to include("La Hulotte")
      expect(response.body).to include("3 adulte(s)")
      expect(response.body).to include("1 enfant(s)")
    end

    it "liste la section ESPACES (nom de l'espace)" do
      expect(response.body).to include("Espaces")
      expect(response.body).to include("Grande Salle")
    end

    it "liste la section CAMPING (kind + personnes)" do
      expect(response.body).to include("Camping")
      expect(response.body).to include("5 personne(s)")
    end

    it "liste la section VAN (véhicules)" do
      expect(response.body).to include("Van")
      expect(response.body).to include("2 véhicule(s)")
    end

    it "liste la section REPAS (libellé + convives)" do
      expect(response.body).to include("Repas")
      expect(response.body).to include("Buffet pain-fromages")
      expect(response.body).to include("8 personne(s)")
    end

    it "conserve la gestion d'activités (epic #55, Phase 6) sans régression" do
      # Turbo-frame d'ancrage + activité listée + formulaire d'ajout toujours là.
      expect(response.body).to include("stay_#{stay.id}_activities")
      expect(response.body).to include("Balade ânes")
      expect(response.body).to include("Ajouter une activité")
    end

    it "expose un lien « Modifier le séjour » vers le form d'édition Phase 1" do
      expect(response.body).to include("Modifier le séjour")
      expect(response.body).to include(edit_stay_path(stay))
    end

    it "conserve le formulaire de réassignation client (anti-régression)" do
      expect(response.body).to include("Assigner ce séjour à un client")
      expect(response.body).to include('name="stay_ids[]"')
    end
  end
end
