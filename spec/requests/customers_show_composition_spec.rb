require "rails_helper"

# Fiche client (customers#show) — la liste des séjours affiche, pour chaque
# séjour, LE MONTANT TOTAL et UNE ICÔNE PAR TYPE DE RESSOURCE qui le compose
# (hébergement, salle, cuisine, van, tente, activité). Une icône par TYPE présent,
# jamais par occurrence. Le hamac n'est pas persisté côté séjour → jamais d'icône.
RSpec.describe "Customers#show — total + icônes de composition des séjours", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)    { User.create!(email: "compo-fiche@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(email: "compo-client@example.com", customer_type: "individual", first_name: "Ada", last_name: "Lovelace") }
  let(:lodging)  { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  # Codes réels de prod (pas les codes des seeds) : salle vs cuisine résolus par
  # motif sur code + nom.
  let(:hall)     { Space.create!(name: "Grande salle", code: "Grande salle", capacity: 40) }
  let(:kitchen)  { Space.create!(name: "Cuisine", code: "Cuisine", capacity: 1) }

  let(:from) { Date.today + 30 }
  let(:to)   { Date.today + 32 }

  let(:porteur)      { Human.create!(name: "Porteuse", email: "porteuse-compo@example.com") }
  let(:experience)   { Experience.create!(name: "Balade ânes", human: porteur, fixed_price_cents: 4000, price_cents: 1500) }
  let(:availability) { ExperienceAvailability.create!(experience: experience, available_on: from + 1, starts_at: "10:00") }

  # Un séjour composite : hébergement + salle + cuisine + tente + van + activité.
  let!(:composite) do
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: from, departure_date: to, total_amount_cents: 137_500)

    booking = Booking.create!(firstname: "Ada", lastname: "Lovelace", group_name: "Les Analytiques",
                              lodging: lodging, from_date: from, to_date: to,
                              adults: 3, status: "confirmed", booking_type: "lodging", price_cents: 97_000)
    stay.stay_items.create!(bookable: booking)

    hall_booking = SpaceBooking.create!(firstname: "Ada", group_name: "Les Analytiques",
                                        from_date: from, to_date: from, status: "confirmed", price_cents: 12_000)
    SpaceReservation.create!(space: hall, space_booking: hall_booking, date: from)
    stay.stay_items.create!(bookable: hall_booking)

    kitchen_booking = SpaceBooking.create!(firstname: "Ada", group_name: "Les Analytiques",
                                           from_date: from, to_date: from, status: "confirmed", price_cents: 5_000)
    SpaceReservation.create!(space: kitchen, space_booking: kitchen_booking, date: from)
    stay.stay_items.create!(bookable: kitchen_booking)

    camping = CampingBooking.create!(firstname: "Ada", group_name: "Les Analytiques",
                                     from_date: from, to_date: to, people: 5, kind: "tente",
                                     status: "confirmed", price_cents: 9_000)
    stay.stay_items.create!(bookable: camping)

    van = VanBooking.create!(firstname: "Ada", group_name: "Les Analytiques",
                             from_date: from, to_date: to, vehicles: 2, status: "confirmed", price_cents: 6_000)
    stay.stay_items.create!(bookable: van)

    ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 4, status: "confirmed")
    stay
  end

  # Un séjour hébergement-seul : uniquement l'icône 🏠.
  let!(:lodging_only) do
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: from + 10, departure_date: from + 12, total_amount_cents: 48_500)
    booking = Booking.create!(firstname: "Ada", lastname: "Lovelace", group_name: "Solo",
                              lodging: lodging, from_date: from + 10, to_date: from + 12,
                              adults: 2, status: "confirmed", booking_type: "lodging", price_cents: 48_500)
    stay.stay_items.create!(bookable: booking)
    stay
  end

  before { sign_in admin }

  def money(cents)
    ApplicationController.helpers.humanized_money_with_symbol(Money.new(cents))
  end

  describe "GET /customers/:id" do
    before { get customer_path(customer) }

    it "répond OK" do
      expect(response).to have_http_status(:ok)
    end

    it "affiche le montant total formaté de chaque séjour" do
      expect(response.body).to include(money(137_500)) # séjour composite
      expect(response.body).to include(money(48_500))  # séjour hébergement-seul
    end

    it "affiche une icône par type de ressource du séjour composite" do
      expect(response.body).to include('title="Hébergement"')
      expect(response.body).to include('title="Salle"')
      expect(response.body).to include('title="Cuisine"')
      expect(response.body).to include('title="Van"')
      expect(response.body).to include('title="Tente"')
      expect(response.body).to include('title="Activité"')
      # Les emojis attendus sont bien rendus.
      expect(response.body).to include("🏠", "🏛️", "🍳", "🚐", "⛺", "🎯")
    end

    it "n'affiche jamais d'icône hamac (non persisté côté séjour)" do
      expect(response.body).not_to include("🛌")
      expect(response.body).not_to include('title="Hamac"')
    end
  end

  describe "séjour hébergement-seul" do
    it "n'affiche que l'icône hébergement (aucune autre ressource)" do
      lodging_only # matérialise le séjour hébergement-seul
      # Isole ce client sur son seul séjour hébergement-seul.
      solo = Customer.create!(email: "solo-lodging@example.com", customer_type: "individual", first_name: "Grace")
      stay = Stay.create!(customer: solo, source: "manual", status: "confirmed",
                          arrival_date: from, departure_date: to, total_amount_cents: 48_500)
      booking = Booking.create!(firstname: "Grace", lastname: "Hopper", group_name: "Solo",
                                lodging: lodging, from_date: from, to_date: to,
                                adults: 2, status: "confirmed", booking_type: "lodging", price_cents: 48_500)
      stay.stay_items.create!(bookable: booking)

      get customer_path(solo)

      expect(response.body).to include('title="Hébergement"')
      expect(response.body).to include("🏠")
      expect(response.body).not_to include('title="Salle"')
      expect(response.body).not_to include('title="Cuisine"')
      expect(response.body).not_to include('title="Van"')
      expect(response.body).not_to include('title="Tente"')
      expect(response.body).not_to include('title="Activité"')
    end
  end

  describe "activité annulée / refusée" do
    it "n'affiche pas l'icône activité si la seule activité est annulée" do
      dead = Customer.create!(email: "dead-activity@example.com", customer_type: "individual", first_name: "Nulle")
      stay = Stay.create!(customer: dead, source: "manual", status: "confirmed",
                          arrival_date: from, departure_date: to, total_amount_cents: 48_500)
      booking = Booking.create!(firstname: "N", lastname: "N", group_name: "N", lodging: lodging,
                                from_date: from, to_date: to, adults: 1, status: "confirmed",
                                booking_type: "lodging", price_cents: 48_500)
      stay.stay_items.create!(bookable: booking)
      ExperienceBooking.create!(experience_availability: availability, stay: stay, participants: 2, status: "cancelled")

      get customer_path(dead)

      expect(response.body).to include('title="Hébergement"')
      expect(response.body).not_to include('title="Activité"')
    end
  end
end
