require "rails_helper"

# Epic #66, Phase 3 — Camping / van / repas dans la composition du Séjour admin.
# Le CRUD admin crée/édite un CampingBooking, un VanBooking (StayItem) et des
# MealOrder (direct), permet un séjour camping-seul, et n'appelle jamais Stripe.
RSpec.describe "Stays — camping / van / repas (epic #66, Phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-camping@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 } # 2 nuits

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: "", status: "pending"
      }.merge(overrides)
    }
  end

  describe "POST /stays — séjour camping-seul" do
    it "crée un CampingBooking + StayItem, sans Booking, avec dates au séjour" do
      expect {
        post stays_path, params: base_params(camping: { people: 4 })
      }.to change(Stay, :count).by(1)
       .and change(CampingBooking, :count).by(1)
       .and change(Booking, :count).by(0)

      stay = Stay.order(:created_at).last
      cb = stay.stay_items.where(bookable_type: "CampingBooking").first.bookable
      expect(cb.people).to eq(4)
      expect(cb.from_date).to eq(arrival)
      expect(cb.to_date).to eq(departure)
      # 4 pers × 2 nuits × 7,50 € = 6 000 c.
      expect(stay.total_amount_cents).to eq(6_000)
      expect(stay.arrival_date).to eq(arrival)
      expect(stay.payments).to be_empty
    end
  end

  describe "POST /stays — van + repas avec hébergement" do
    it "persiste VanBooking (StayItem) + MealOrder (direct)" do
      expect {
        post stays_path, params: base_params(
          lodging_id: lodging.id,
          van: { vehicles: 2 },
          meals: { "0" => { kind: "buffet", date: arrival.iso8601, people: 3 } }
        )
      }.to change(VanBooking, :count).by(1)
       .and change(MealOrder, :count).by(1)

      stay = Stay.order(:created_at).last
      van = stay.stay_items.where(bookable_type: "VanBooking").first.bookable
      expect(van.vehicles).to eq(2)
      meal = stay.meal_orders.first
      expect(meal.kind).to eq("buffet")
      expect(meal.people).to eq(3)
      expect(meal.date).to eq(arrival)
    end
  end

  describe "PATCH /stays/:id — édition d'un séjour camping-seul" do
    def create_camping_only_stay
      draft = Reservations::Draft.new(
        lodging_id: nil, arrival_date: arrival, departure_date: departure,
        first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222",
        campings: [{ kind: "tente", people: 3, nights: 2 }]
      )
      Reservations::Builder.new(draft: draft, admin: true, source: "manual").tap(&:run!).stay
    end

    def update_params(stay, overrides = {})
      {
        stay: {
          customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: "", status: "pending"
        }.merge(overrides)
      }
    end

    it "préremplit le form d'édition avec le camping existant" do
      stay = create_camping_only_stay
      get edit_stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Camping (tente)")
      expect(response.body).to include('value="3"') # people prérempli
    end

    it "change le nombre de personnes et recalcule le total" do
      stay = create_camping_only_stay
      expect(stay.total_amount_cents).to eq(4_500) # 3 × 2 × 7,50 €

      patch stay_path(stay), params: update_params(stay, camping: { people: 5 })
      expect(response).to redirect_to(recent_stays_path)

      stay.reload
      cb = stay.stay_items.where(bookable_type: "CampingBooking").first.bookable
      expect(cb.people).to eq(5)
      expect(stay.total_amount_cents).to eq(7_500) # 5 × 2 × 7,50 €
    end

    it "retire le camping (0 pers) sans autre composant → refusé (séjour vide)" do
      stay = create_camping_only_stay
      patch stay_path(stay), params: update_params(stay, camping: { people: 0 })
      expect(response).to have_http_status(:unprocessable_entity)
      # Issue #80 : la contrainte de composition s'élargit aux activités/repas.
      expect(response.body).to include("un emplacement camping/van, une activité ou un repas")
    end
  end

  describe "capacité globale — force-dispo (création)" do
    it "force le camping au-delà de la capacité avec avertissement" do
      CampingBooking.create!(
        firstname: "Occ", from_date: arrival, to_date: departure,
        people: CampingBooking::TOTAL_CAPACITY, status: "confirmed", kind: "tente"
      )
      post stays_path, params: base_params(camping: { people: 2 }, force_availability: "1")
      expect(response).to redirect_to(recent_stays_path)
      expect(flash[:alert]).to match(/forçant la disponibilité/i)
      expect(CampingBooking.where(status: "pending").count).to eq(1)
    end

    it "bloque hors force" do
      CampingBooking.create!(
        firstname: "Occ", from_date: arrival, to_date: departure,
        people: CampingBooking::TOTAL_CAPACITY, status: "confirmed", kind: "tente"
      )
      expect {
        post stays_path, params: base_params(camping: { people: 2 })
      }.not_to change(Stay, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to match(/complet/i)
    end
  end
end
