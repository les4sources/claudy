require "rails_helper"

RSpec.describe "Stays (détails admin)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-stays@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "stayshow@example.com", customer_type: "individual") }
  let(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 2, 14),
                 departure_date: Date.new(2026, 2, 15), status: "confirmed", total_amount_cents: 12_000)
  end
  let!(:booking) do
    Booking.create!(firstname: "Jean", lastname: "Dupont", group_name: "Les Amis",
                    from_date: Date.new(2026, 2, 14), to_date: Date.new(2026, 2, 15),
                    adults: 2, status: "confirmed")
  end

  before { stay.stay_items.create!(bookable: booking) }

  describe "GET /stays/:id" do
    it "renders the stay details fragment with French dates" do
      get stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Séjour ##{stay.id}")
      expect(response.body).to include("14 février 2026")
      expect(response.body).to include("Confirmé") # statut en label
    end

    # Le contact porté par la réservation d'origine a quitté la modale (Michael
    # 2026-07-28) : il doublonnait le bloc Client juste en dessous. Il reste
    # visible dans le formulaire d'édition (cf. stays_origin_contact_spec).
    it "n'affiche plus le bloc Contact de la réservation d'origine" do
      get stay_path(stay)
      expect(response.body).not_to include("Jean Dupont")
    end

    it "shows the OTA platform badge for an Airbnb booking" do
      airbnb_stay = Stay.create!(customer: customer, arrival_date: Date.new(2026, 3, 1), departure_date: Date.new(2026, 3, 2), status: "confirmed")
      airbnb_booking = Booking.create!(firstname: "Guest", from_date: Date.new(2026, 3, 1), to_date: Date.new(2026, 3, 2), adults: 2, status: "confirmed", platform: "airbnb")
      airbnb_stay.stay_items.create!(bookable: airbnb_booking)

      get stay_path(airbnb_stay)
      expect(response.body).to include("Airbnb")
    end

    it "shows no platform badge for a direct booking" do
      get stay_path(stay) # booking ci-dessus = plateforme par défaut (nil/direct)
      expect(response.body).not_to include("Booking.com")
      expect(response.body).not_to match(/>\s*Airbnb\s*</)
    end

    # Adresse du client sous son nom (Michael 2026-08-29) : on répond au client
    # depuis la modale, sans détour par la fiche client.
    it "affiche l'adresse du client en lien mailto sous son nom" do
      get stay_path(stay)
      expect(response.body).to include('href="mailto:stayshow@example.com"')
    end

    it "ne propose jamais l'adresse du fourre-tout en mailto" do
      catch_all = Customer.create!(email: Customer::CATCH_ALL_EMAIL, customer_type: "individual")
      orphan = Stay.create!(customer: catch_all, arrival_date: Date.new(2026, 4, 1),
                            departure_date: Date.new(2026, 4, 2), status: "confirmed")

      get stay_path(orphan)
      expect(response.body).not_to include("mailto:#{Customer::CATCH_ALL_EMAIL}")
    end

    # Sur un fourre-tout, la seule adresse qui joint vraiment quelqu'un est celle
    # portée par la réservation d'origine.
    it "affiche l'adresse de la réservation d'origine sur un séjour fourre-tout" do
      catch_all = Customer.create!(email: Customer::OTA_CATCH_ALL_EMAILS["airbnb"], customer_type: "individual")
      legacy = Stay.create!(customer: catch_all, arrival_date: Date.new(2026, 5, 1),
                            departure_date: Date.new(2026, 5, 2), status: "confirmed")
      legacy.stay_items.create!(bookable: Booking.create!(firstname: "Freya", email: "freya@example.com",
                                                          from_date: Date.new(2026, 5, 1), to_date: Date.new(2026, 5, 2),
                                                          adults: 2, status: "confirmed", platform: "airbnb"))

      get stay_path(legacy)
      expect(response.body).to include('href="mailto:freya@example.com"')
    end

    it "includes a reassign form prefilled from the booking (name + group, email blank)" do
      get stay_path(stay)
      expect(response.body).to include("Réassigner le client")
      expect(response.body).to include('data-controller="reassign-form"')
      expect(response.body).to include("Rechercher un client") # recherche dynamique
      expect(response.body).to include('value="Jean"')         # prénom pré-rempli
      expect(response.body).to include('value="Dupont"')       # nom pré-rempli
      expect(response.body).to include('value="Les Amis"')     # groupe pré-rempli
      # le stay courant est embarqué pour ne réassigner que lui
      expect(response.body).to include('name="stay_ids[]"')
    end
  end
end
