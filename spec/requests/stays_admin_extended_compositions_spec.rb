require "rails_helper"

# Issue #80 — compositions de séjour élargies. Trois nouvelles compositions
# légitimes (validées par Michael), sans hébergement ni nuitée :
#   1. activités seules (ExperienceBooking) ;
#   2. repas seuls (MealOrder) ;
#   3. location d'espace en journée sèche (0 nuit).
# Pour chacune : création OK, agrégats (dates dérivées de l'élément présent) et
# total corrects.
RSpec.describe "Stays — compositions élargies (issue #80)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-ext@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:day) { Date.today + 30 }

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222" },
        arrival_date: "", departure_date: "",
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: "", status: "pending"
      }.merge(overrides)
    }
  end

  describe "POST /stays — activités seules" do
    it "crée un séjour sans hébergement, daté du créneau, au bon total" do
      exp   = Experience.create!(name: "Balade ânes", fixed_price_cents: 4_000, price_cents: 1_500)
      avail = ExperienceAvailability.create!(experience: exp, available_on: day, starts_at: "10:00")

      expect {
        post stays_path, params: base_params(experiences: { "0" => { availability_id: avail.id, participants: 2 } })
      }.to change(Stay, :count).by(1)
       .and change(ExperienceBooking, :count).by(1)
       .and change(Booking, :count).by(0)

      expect(response).to redirect_to(recent_stays_path)
      stay = Stay.order(:created_at).last
      eb   = stay.experience_bookings.first
      expect(stay.stay_items).to be_empty
      expect(stay.total_amount_cents).to eq(eb.price_cents)
      expect(eb.price_cents).to be_positive
      # Dates dérivées du créneau de l'activité (aucune nuitée saisie).
      expect(stay.arrival_date).to eq(day)
      expect(stay.departure_date).to eq(day)
    end
  end

  describe "POST /stays — repas seuls" do
    it "crée un séjour sans hébergement, daté du repas, au bon total" do
      expect {
        post stays_path, params: base_params(meals: { "0" => { kind: "buffet", date: day.iso8601, people: 3 } })
      }.to change(Stay, :count).by(1)
       .and change(MealOrder, :count).by(1)
       .and change(Booking, :count).by(0)

      expect(response).to redirect_to(recent_stays_path)
      stay = Stay.order(:created_at).last
      expect(stay.stay_items).to be_empty
      # buffet 12 €/pers × 3 = 3 600 c.
      expect(stay.total_amount_cents).to eq(3_600)
      expect(stay.arrival_date).to eq(day)
      expect(stay.departure_date).to eq(day)
    end
  end

  describe "POST /stays — espace en journée sèche (0 nuit)" do
    let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }

    it "crée un SpaceBooking daté du jour, à 0 nuit, au forfait espace" do
      expect {
        post stays_path, params: base_params(
          arrival_date: day.iso8601, departure_date: day.iso8601, # même jour → 0 nuit
          halls: { "0" => { kind: "grande_salle", date: day.iso8601, period: "journee" } }
        )
      }.to change(Stay, :count).by(1)
       .and change(SpaceBooking, :count).by(1)
       .and change(Booking, :count).by(0)

      expect(response).to redirect_to(recent_stays_path)
      stay = Stay.order(:created_at).last
      sb = stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
      expect(sb.space_reservations.map(&:space)).to eq([grande_salle])
      # Forfait espace journée (indépendant du nombre de nuits) : 290 €.
      expect(stay.total_amount_cents).to eq(29_000)
      expect(stay.arrival_date).to eq(day)
      expect(stay.departure_date).to eq(day)
    end
  end

  describe "édition (AdminUpdater) — bascule vers activités seules" do
    it "accepte de retirer l'hébergement au profit d'activités seules" do
      # Séjour hébergement-seul via le Builder admin.
      lodging = Lodging.create!(name: "La Hulotte", summary: "gîte")
      draft = Reservations::Draft.new(
        lodging_id: lodging.id, arrival_date: day, departure_date: day + 2,
        adults: 2, dogs_count: 0,
        first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222"
      )
      builder = Reservations::Builder.new(draft: draft, admin: true, source: "manual")
      builder.run!
      stay = builder.stay

      exp   = Experience.create!(name: "Poterie", price_cents: 2_000)
      avail = ExperienceAvailability.create!(experience: exp, available_on: day + 1, starts_at: "14:00")

      patch stay_path(stay), params: {
        stay: {
          customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
          arrival_date: "", departure_date: "", adults: 2, children: 0, dogs_count: 0,
          lodging_id: "", status: "pending",
          experiences: { "0" => { availability_id: avail.id, participants: 1 } }
        }
      }
      expect(response).to redirect_to(recent_stays_path)

      stay.reload
      expect(stay.stay_items.where(bookable_type: "Booking").where(deleted_at: nil)).to be_empty
      expect(stay.experience_bookings.active.count).to eq(1)
      expect(stay.arrival_date).to eq(day + 1) # date dérivée du créneau restant
    end
  end
end
