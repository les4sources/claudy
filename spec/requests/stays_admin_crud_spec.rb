require "rails_helper"

# CRUD Séjour admin (epic #66, Phase 1) — le séjour devient le point d'entrée de
# création composable côté admin (hébergement + activités), en réutilisant
# `Reservations::Builder` en mode admin : aucun Stripe, aucun email forcé,
# force-dispo avec avertissement, statut au choix, client existant ou à la volée.
RSpec.describe "Stays — CRUD admin (epic #66)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-stays@les4sources.be", password: "password123") }
  before { sign_in user }

  # Hébergement tarifé au barème B2C (Pricing::Catalog) : La Hulotte = 485 € la
  # 1re nuit + 260 € par nuit suivante. 2 nuits → 745 € (74 500 cents).
  let!(:lodging)  { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }
  let(:hulotte_two_nights_cents) { 74_500 }

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: lodging.id, status: "pending"
      }.merge(overrides)
    }
  end

  # Crée un séjour admin directement via le Builder (helper pour edit/update/destroy).
  def create_admin_stay(status: "pending")
    draft = Reservations::Draft.new(
      lodging_id: lodging.id, arrival_date: arrival, departure_date: departure,
      adults: 2, first_name: "Alice", last_name: "Martin",
      email: "alice@example.com", phone: "0470111222"
    )
    builder = Reservations::Builder.new(draft: draft, admin: true, status: status, source: "manual")
    builder.run!
    builder.stay
  end

  describe "GET /stays/new" do
    it "affiche le formulaire de composition" do
      get new_stay_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nouveau séjour")
      expect(response.body).to include("La Hulotte")
      expect(response.body).to include("Forcer la disponibilité")
    end
  end

  describe "POST /stays (create)" do
    it "crée un séjour avec un nouveau client, une occupation d'hébergement et AUCUN paiement" do
      expect {
        post stays_path, params: base_params
      }.to change(Stay, :count).by(1)
       .and change(Customer, :count).by(1)
       .and change(Booking, :count).by(1)

      expect(response).to redirect_to(recent_stays_path)
      stay = Stay.order(:created_at).last
      expect(stay.source).to eq("manual")
      expect(stay.status).to eq("pending")
      expect(stay.customer.email).to eq("alice@example.com")
      expect(stay.total_amount_cents).to eq(hulotte_two_nights_cents)
      # Décision figée : aucun paiement (donc aucun appel Stripe) à la création admin.
      expect(stay.payments).to be_empty
    end

    it "réutilise un client existant sélectionné par id (pas de doublon)" do
      customer = Customer.create!(email: "bob@example.com", first_name: "Bob", customer_type: "individual")
      expect {
        post stays_path, params: base_params(customer_mode: "existing", customer_id: customer.id, new_customer: {})
      }.to change(Stay, :count).by(1).and change(Customer, :count).by(0)

      expect(Stay.order(:created_at).last.customer).to eq(customer)
    end

    it "laisse l'admin choisir le statut confirmé" do
      post stays_path, params: base_params(status: "confirmed")
      expect(Stay.order(:created_at).last.status).to eq("confirmed")
    end

    it "bloque la création sur des dates indisponibles hors force" do
      Unavailability.create!(lodging: lodging, date: arrival)
      expect { post stays_path, params: base_params }.not_to change(Stay, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("plus disponibles")
    end

    it "force la création sur des dates indisponibles avec un avertissement" do
      Unavailability.create!(lodging: lodging, date: arrival)
      expect {
        post stays_path, params: base_params(force_availability: "1")
      }.to change(Stay, :count).by(1)

      expect(response).to redirect_to(recent_stays_path)
      expect(flash[:alert]).to include("forçant la disponibilité")
    end

    it "attache les activités sélectionnées et les intègre au total" do
      exp   = Experience.create!(name: "Balade ânes", fixed_price_cents: 4_000, price_cents: 1_500)
      avail = ExperienceAvailability.create!(experience: exp, available_on: arrival + 1, starts_at: "10:00")

      post stays_path, params: base_params(experiences: { "0" => { availability_id: avail.id, participants: 2 } })

      stay = Stay.order(:created_at).last
      expect(stay.experience_bookings.count).to eq(1)
      # Activité : 40 € forfait + 15 €/pers × 2 = 70 € (7 000 cents). Total = 745 € + 70 €.
      expect(stay.total_amount_cents).to eq(hulotte_two_nights_cents + 7_000)
    end
  end

  describe "GET /stays/:id/edit" do
    it "affiche le formulaire prérempli" do
      stay = create_admin_stay
      get edit_stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Modifier le séjour ##{stay.id}")
      expect(response.body).to include("La Hulotte")
    end
  end

  describe "PATCH /stays/:id (update)" do
    let!(:cheveche) { Lodging.create!(name: "La Chevêche", summary: "gîte") }

    def update_params(stay, overrides = {})
      {
        stay: {
          customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: lodging.id, status: "pending"
        }.merge(overrides)
      }
    end

    it "modifie l'hébergement et recalcule le total" do
      stay = create_admin_stay
      patch stay_path(stay), params: update_params(stay, lodging_id: cheveche.id)
      expect(response).to redirect_to(recent_stays_path)

      stay.reload
      booking = stay.stay_items.where(bookable_type: "Booking").first.bookable
      expect(booking.lodging_id).to eq(cheveche.id)
      # La Chevêche = 275 € + 200 € = 475 € (47 500 cents) sur 2 nuits.
      expect(stay.total_amount_cents).to eq(47_500)
    end

    it "bascule le statut en confirmé SANS envoyer d'email au client" do
      stay = create_admin_stay
      ActionMailer::Base.deliveries.clear
      patch stay_path(stay), params: update_params(stay, status: "confirmed")

      expect(stay.reload.status).to eq("confirmed")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "ajoute une activité à un séjour existant" do
      stay  = create_admin_stay
      exp   = Experience.create!(name: "Poterie", price_cents: 2_000)
      avail = ExperienceAvailability.create!(experience: exp, available_on: arrival + 1, starts_at: "14:00")

      expect {
        patch stay_path(stay), params: update_params(stay, experiences: { "0" => { availability_id: avail.id, participants: 3 } })
      }.to change { stay.experience_bookings.active.count }.from(0).to(1)

      expect(stay.reload.total_amount_cents).to eq(hulotte_two_nights_cents + 6_000) # 20 €/pers × 3
    end

    it "retire une activité en passant ses participants à 0" do
      stay  = create_admin_stay
      exp   = Experience.create!(name: "Poterie", price_cents: 2_000)
      avail = ExperienceAvailability.create!(experience: exp, available_on: arrival + 1, starts_at: "14:00")
      stay.experience_bookings.create!(experience_availability: avail, participants: 2, status: "pending")

      expect {
        patch stay_path(stay), params: update_params(stay, experiences: { "0" => { availability_id: avail.id, participants: 0 } })
      }.to change { stay.experience_bookings.active.count }.from(1).to(0)
    end
  end

  describe "prix imposé & attribution (epic #81, Phase 3)" do
    def update_params(stay, overrides = {})
      {
        stay: {
          customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: lodging.id, status: "pending"
        }.merge(overrides)
      }
    end

    it "POST impose le total via price_override et enregistre source + plateforme" do
      post stays_path, params: base_params(price_override: "999", source: "ota", platform: "airbnb")
      expect(response).to redirect_to(recent_stays_path)

      stay = Stay.order(:created_at).last
      expect(stay.price_override_cents).to eq(99_900)
      expect(stay.total_amount_cents).to eq(99_900)          # override, pas 74 500
      expect(stay.source).to eq("ota")
      booking = stay.stay_items.where(bookable_type: "Booking").first.bookable
      expect(booking.platform).to eq("airbnb")
    end

    it "POST sans price_override applique le devis B2C" do
      post stays_path, params: base_params
      expect(Stay.order(:created_at).last.total_amount_cents).to eq(hulotte_two_nights_cents)
    end

    it "PATCH pose puis retire l'override (retour au devis)" do
      stay = create_admin_stay

      patch stay_path(stay), params: update_params(stay, price_override: "500")
      expect(stay.reload.price_override_cents).to eq(50_000)
      expect(stay.total_amount_cents).to eq(50_000)

      patch stay_path(stay), params: update_params(stay, price_override: "")
      expect(stay.reload.price_override_cents).to be_nil
      expect(stay.total_amount_cents).to eq(hulotte_two_nights_cents) # devis repris
    end
  end

  describe "DELETE /stays/:id (destroy)" do
    it "soft-supprime le séjour (jamais de hard destroy)" do
      stay = create_admin_stay
      delete stay_path(stay)

      expect(response).to redirect_to(recent_stays_path)
      expect(Stay.exists?(stay.id)).to be(false)                     # hors default scope
      expect(Stay.unscoped.find(stay.id).deleted_at).to be_present   # présent mais marqué supprimé
    end
  end
end
