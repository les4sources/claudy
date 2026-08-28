require "rails_helper"

# Bandeau « Aujourd'hui » du calendrier (2026-08-28). Il listait les RÉSERVABLES :
# une boucle sur les Booking, puis une autre sur les SpaceBooking — un séjour qui
# loue un gîte ET des salles y apparaissait deux fois. On couvre les trois choses
# qui font que la carte est bien celle du SÉJOUR : l'unicité, la composition
# complète, et le départ du jour (dernière nuit = hier).
RSpec.describe Calendar::TodayStayCards do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }
  let!(:petite_salle) { Space.create!(name: "Petite Salle", capacity: 1) }

  def draft(arrival:, departure:, halls: [], email: "camille@example.com")
    Reservations::Draft.new(
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: email, phone: "+32470112233", halls: halls
    )
  end

  def hall(date:, kind: "grande_salle", period: "journee")
    { kind: kind, date: date.iso8601, period: period }
  end

  def build_stay(arrival:, departure:, halls: [], email: "camille@example.com")
    builder = Reservations::Builder.new(
      draft: draft(arrival: arrival, departure: departure, halls: halls, email: email),
      admin: true, status: "confirmed", source: "manual"
    )
    builder.run!
    builder.stay
  end

  # Reproduit ce que `PagesController#calendar` charge, en plus étroit.
  def panel(date: Date.today)
    window = (date - 7)..(date + 7)
    described_class.new(
      date: date,
      grouped_reservations: Reservation.includes(booking: [:lodging, { stay: :customer }])
                                       .where(date: window).to_a.group_by(&:date),
      grouped_space_reservations: SpaceReservation.includes(:space, space_booking: { stay: :customer })
                                                  .where(date: window).to_a.group_by(&:date),
      grouped_camping_bookings: {},
      grouped_van_bookings: {},
      grouped_hamac_bookings: {}
    )
  end

  describe "un séjour gîte + salles" do
    let!(:stay) do
      build_stay(arrival: Date.today, departure: Date.today + 2,
                 halls: [hall(date: Date.today), hall(date: Date.today, kind: "petite_salle")])
    end

    it "rend UNE seule carte, et non une par réservable" do
      cards = panel.cards
      expect(cards.size).to eq(1)
      expect(cards.first.stay.id).to eq(stay.id)
    end

    it "porte l'hébergement ET les espaces sur la même carte" do
      card = panel.cards.first
      expect(card.block.booking_groups.map { |g| g.booking.lodging.name }).to eq(["La Hulotte"])
      expect(card.block.space_groups.flat_map { |g| g.space_reservations.map { |sr| sr.space.name } })
        .to match_array(["Grande Salle", "Petite Salle"])
    end

    it "annonce une arrivée" do
      expect(panel.cards.first.state).to eq(:checkin)
    end
  end

  describe "le départ du jour" do
    # Nuits [arrivée, départ) : un séjour qui part aujourd'hui n'a AUCUNE
    # occupation datée d'aujourd'hui — sa dernière nuit est celle d'hier.
    let!(:stay) { build_stay(arrival: Date.today - 2, departure: Date.today) }

    it "apparaît quand même, en check-out" do
      cards = panel.cards
      expect(cards.map { |c| c.stay.id }).to eq([stay.id])
      expect(cards.first.state).to eq(:checkout)
      expect(cards.first.block.booking_groups).to be_present
    end
  end

  describe "un départ qui garde une salle jusqu'au soir" do
    let!(:stay) do
      build_stay(arrival: Date.today - 2, departure: Date.today,
                 halls: [hall(date: Date.today)])
    end

    it "réunit les chambres d'hier et la salle d'aujourd'hui sur une seule carte" do
      cards = panel.cards
      expect(cards.size).to eq(1)
      card = cards.first
      expect(card.block.booking_groups).to be_present
      expect(card.block.space_groups.flat_map { |g| g.space_reservations.map { |sr| sr.space.name } })
        .to eq(["Grande Salle"])
    end
  end

  describe "une location de salle à la journée" do
    let!(:stay) do
      builder = Reservations::Builder.new(
        draft: Reservations::Draft.new(
          arrival_date: Date.today.iso8601, departure_date: Date.today.iso8601,
          dogs_count: 0, first_name: "Colette", last_name: "Dubois",
          email: "colette@example.com", phone: "+32470112244",
          halls: [hall(date: Date.today)]
        ),
        admin: true, status: "confirmed", source: "manual"
      )
      builder.run!
      builder.stay
    end

    it "est annoncée comme arrivée ET départ" do
      expect(panel.cards.map(&:state)).to eq([:dayuse])
    end
  end

  describe "l'ordre du bandeau" do
    let!(:partant)  { build_stay(arrival: Date.today - 2, departure: Date.today, email: "part@example.com") }
    let!(:arrivant) { build_stay(arrival: Date.today, departure: Date.today + 2, email: "arrive@example.com") }

    it "montre les départs avant les arrivées" do
      expect(panel.cards.map(&:state)).to eq([:checkout, :checkin])
    end
  end

  describe "une occupation sans séjour rattaché" do
    let!(:orpheline) do
      booking = Booking.create!(firstname: "OTA", from_date: Date.today, to_date: Date.today + 1,
                                adults: 2, status: "confirmed", lodging: hulotte)
      Reservation.create!(booking: booking, room: hulotte.rooms.first, date: Date.today)
      booking
    end

    it "reste rendue à part, jamais perdue" do
      expect(panel.cards).to be_empty
      expect(panel.orphan_booking_groups.map { |g| g.booking.id }).to eq([orpheline.id])
    end
  end
end
