require "rails_helper"

# Epic #66, Phase 3 — Camping / van / repas persistés. En mode admin, le Builder
# crée un CampingBooking + un VanBooking (StayItem, occupent le calendrier) et des
# MealOrder (has_many direct, hors calendrier). La part de prix de chacun est
# EXTRAITE de `lodging_bundle_cents` (tags de catégorie) et portée par son propre
# modèle → aucun double-compte. Le funnel public reste devis-only (inchangé).
RSpec.describe Reservations::Builder, "camping / van / repas (epic #66, Phase 3)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 } # 2 nuits
  let(:hulotte_two_nights_cents) { 74_500 }
  let(:grande_salle_journee_cents) { 29_000 }

  def draft(**overrides)
    Reservations::Draft.new({
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233"
    }.merge(overrides))
  end

  describe "persistance admin camping + van + repas" do
    it "crée CampingBooking + VanBooking (StayItem) et MealOrder (direct)" do
      d = draft(
        lodging_id: hulotte.id,
        campings: [{ kind: "tente", people: 3, nights: 2 }],
        vans:     [{ nights: 2 }],
        meals:    [{ kind: "buffet", date: arrival.iso8601, people: 4 }]
      )
      builder = described_class.new(draft: d, admin: true, source: "manual")
      expect(builder.run).to be(true)

      camping = builder.camping_booking
      van     = builder.van_booking
      expect(camping).to be_persisted
      expect(van).to be_persisted
      expect(camping.people).to eq(3)
      expect(van.vehicles).to eq(1)
      # Camping 3 pers × 2 nuits × 7,50 € = 4 500 c ; van 2 nuits × 15 € = 3 000 c.
      expect(camping.price_cents).to eq(4_500)
      expect(van.price_cents).to eq(3_000)
      # Occupent le calendrier via StayItem.
      expect(builder.stay.stay_items.map(&:bookable)).to include(camping, van)
      # Repas : has_many direct, PAS de StayItem.
      expect(builder.stay.meal_orders.count).to eq(1)
      meal = builder.stay.meal_orders.first
      expect(meal.kind).to eq("buffet")
      expect(meal.people).to eq(4)
      expect(meal.date).to eq(arrival)
      expect(meal.price_cents).to eq(4_800) # 4 × 12 €
      # Occupations camping/van portent les dates du séjour.
      expect(camping.from_date).to eq(arrival)
      expect(camping.to_date).to eq(departure)
      # Aucun Stripe.
      expect(builder.stay.payments).to be_empty
    end
  end

  describe "invariant de ventilation du total (sans double-compte)" do
    let!(:experience) { Experience.create!(name: "Atelier vannerie", fixed_price_cents: 2_000, price_cents: 1_000, max_participants: 8) }
    let!(:slot) { ExperienceAvailability.create!(experience: experience, available_on: arrival, starts_at: "10:00", max_participants: 8) }

    it "Booking(hébergement pur) + SpaceBooking + Camping + Van + Meals + Experiences == total" do
      d = draft(
        lodging_id: hulotte.id,
        halls:      [{ kind: "grande_salle", date: arrival.iso8601, period: "journee" }],
        campings:   [{ kind: "tente", people: 3, nights: 2 }],
        vans:       [{ nights: 2 }],
        meals:      [{ kind: "buffet", date: arrival.iso8601, people: 4 }],
        experiences: [{ id: experience.id, availability_id: slot.id, participants: 2 }]
      )
      builder = described_class.new(draft: d, admin: true, source: "manual")
      expect(builder.run).to be(true)

      booking_cents  = builder.booking.price_cents
      space_cents    = builder.space_booking.price_cents
      camping_cents  = builder.camping_booking.price_cents
      van_cents      = builder.van_booking.price_cents
      meals_cents    = builder.stay.meal_orders.sum(:price_cents)
      exp_cents      = builder.stay.experience_bookings.active.sum(&:price_cents)

      # L'hébergement pur ne contient NI camping NI van NI repas NI espaces.
      expect(booking_cents).to eq(hulotte_two_nights_cents)
      expect(space_cents).to eq(grande_salle_journee_cents)
      expect(camping_cents).to eq(4_500)
      expect(van_cents).to eq(3_000)
      expect(meals_cents).to eq(4_800)
      expect(exp_cents).to eq(4_000) # 2 000 + 1 000 × 2

      sum = booking_cents + space_cents + camping_cents + van_cents + meals_cents + exp_cents
      expect(sum).to eq(builder.stay.total_amount_cents)
      # Et recompute redonne exactement le même total.
      builder.stay.recompute_aggregates!
      expect(builder.stay.reload.total_amount_cents).to eq(sum)
    end
  end

  describe "séjour camping-seul (sans hébergement ni espace)" do
    let(:camping_only) do
      draft(lodging_id: nil, campings: [{ kind: "tente", people: 4, nights: 2 }])
    end

    it "ne crée AUCUN Booking mais persiste le CampingBooking + dates au séjour" do
      builder = described_class.new(draft: camping_only, admin: true, source: "manual")
      expect(builder.run).to be(true)

      expect(builder.booking).to be_nil
      camping = builder.camping_booking
      expect(camping).to be_persisted
      expect(builder.stay.stay_items.map(&:bookable)).to eq([camping])
      # 4 pers × 2 nuits × 7,50 € = 6 000 c.
      expect(builder.stay.total_amount_cents).to eq(6_000)
      expect(builder.stay.arrival_date).to eq(arrival)
      expect(builder.stay.departure_date).to eq(departure)
    end

    it "garde des agrégats corrects après recompute (dates non écrasées)" do
      builder = described_class.new(draft: camping_only, admin: true, source: "manual")
      builder.run
      stay = builder.stay

      stay.recompute_aggregates!
      stay.reload
      expect(stay.total_amount_cents).to eq(6_000)
      expect(stay.arrival_date).to eq(arrival)
      expect(stay.departure_date).to eq(departure)
    end
  end

  describe "séjour van-seul" do
    it "persiste le VanBooking et date le séjour" do
      builder = described_class.new(
        draft: draft(lodging_id: nil, vans: [{ nights: 2 }, { nights: 2 }]),
        admin: true, source: "manual"
      )
      expect(builder.run).to be(true)
      expect(builder.van_booking).to be_persisted
      expect(builder.van_booking.vehicles).to eq(2)
      # 2 véhicules × 2 nuits × 15 € = 6 000 c.
      expect(builder.stay.total_amount_cents).to eq(6_000)
      expect(builder.stay.arrival_date).to eq(arrival)
    end
  end

  describe "capacité globale du camping (dispo + force)" do
    def fill_camping!(people)
      cb = CampingBooking.create!(
        firstname: "Occ", from_date: arrival, to_date: departure,
        people: people, status: "confirmed", kind: "tente"
      )
      cb
    end

    it "bloque hors force quand la capacité globale est dépassée" do
      fill_camping!(CampingBooking::TOTAL_CAPACITY - 1) # reste 1 place
      builder = described_class.new(
        draft: draft(lodging_id: nil, campings: [{ kind: "tente", people: 5, nights: 2 }]),
        admin: true, source: "manual"
      )
      expect(builder.run).to be(false)
      expect(builder.error_message).to match(/complet/i)
      expect(Stay.count).to eq(0)
    end

    it "force la création avec un avertissement" do
      fill_camping!(CampingBooking::TOTAL_CAPACITY - 1)
      builder = described_class.new(
        draft: draft(lodging_id: nil, campings: [{ kind: "tente", people: 5, nights: 2 }]),
        admin: true, source: "manual", skip_availability: true
      )
      expect(builder.run).to be(true)
      expect(builder.availability_warning).to match(/forçant la disponibilité/i)
      expect(builder.camping_booking).to be_persisted
    end
  end

  describe "funnel public inchangé (camping/van/repas devis-only)" do
    it "ne persiste NI CampingBooking NI VanBooking NI MealOrder" do
      d = draft(
        lodging_id: hulotte.id,
        campings: [{ kind: "tente", people: 3, nights: 2 }],
        meals:    [{ kind: "buffet", people: 4 }]
      )
      builder = described_class.new(draft: d) # PAS admin
      expect(builder.run).to be(true)

      expect(CampingBooking.count).to eq(0)
      expect(VanBooking.count).to eq(0)
      expect(builder.stay.meal_orders).to be_empty
      # Le Booking public porte encore le bundle (camping + repas noyés).
      # Total prévu = 74 500 (héberg) + 4 500 (camping) + 4 800 (repas) = 83 800 c.
      expect(builder.stay.total_amount_cents).to eq(83_800)
      expect(builder.booking.price_cents).to eq(83_800)
    end
  end
end
