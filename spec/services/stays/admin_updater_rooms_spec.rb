require "rails_helper"

# Epic #81, Phase 5 — édition d'un séjour en mode chambres seules. L'updater
# reconstruit proprement les Reservation quand les chambres (ou dates/hébergement)
# changent, et ne bloque pas un séjour confirmé par sa propre occupation.
RSpec.describe Stays::AdminUpdater, "chambres seules (epic #81, Phase 5)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << (@room_1 = Room.create!(name: "Chambre 1", level: 1))
    lodging.rooms << (@room_2 = Room.create!(name: "Chambre 2", level: 1))
    lodging.rooms << (@room_3 = Room.create!(name: "Chambre 3", level: 1))
    lodging
  end

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def draft(**overrides)
    Reservations::Draft.new({
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      adults: 2, dogs_count: 0,
      first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233"
    }.merge(overrides))
  end

  # Séjour chambres seules confirmé, sur 2 chambres, via le Builder.
  def create_rooms_stay(room_ids: [@room_1.id, @room_2.id], price_override_cents: 12_000)
    builder = Reservations::Builder.new(
      draft: draft(booking_type: "rooms", room_ids: room_ids),
      admin: true, status: "confirmed", source: "manual",
      price_override_cents: price_override_cents
    )
    builder.run!
    builder.stay
  end

  def booking_of(stay)
    stay.stay_items.where(bookable_type: "Booking").first.bookable
  end

  it "reconstruit les Reservation quand les chambres cochées changent" do
    stay = create_rooms_stay(room_ids: [@room_1.id, @room_2.id])

    updater = described_class.new(
      stay: stay,
      draft: draft(booking_type: "rooms", room_ids: [@room_3.id], price_override_cents: 12_000),
      status: "confirmed", price_override_cents: 12_000
    )
    expect(updater.run).to be(true)

    booking = booking_of(stay.reload)
    expect(booking.reservations.map(&:room_id).uniq).to eq([@room_3.id])
    # 1 chambre × 2 nuits.
    expect(booking.reservations.count).to eq(2)
  end

  it "convertit un séjour gîte entier en chambres seules" do
    entire = Reservations::Builder.new(
      draft: draft, admin: true, status: "confirmed", source: "manual"
    ).tap(&:run!).stay
    expect(booking_of(entire).reservations.map(&:room_id).uniq).to match_array(hulotte.rooms.pluck(:id))

    updater = described_class.new(
      stay: entire,
      draft: draft(booking_type: "rooms", room_ids: [@room_1.id], price_override_cents: 9_000),
      status: "confirmed", price_override_cents: 9_000
    )
    expect(updater.run).to be(true)

    booking = booking_of(entire.reload)
    expect(booking.reservations.map(&:room_id).uniq).to eq([@room_1.id])
    expect(booking.rooms_only_occupation?).to be(true)
  end

  it "ne se bloque pas lui-même en réenregistrant un séjour chambres CONFIRMÉ inchangé" do
    stay = create_rooms_stay(room_ids: [@room_1.id])

    updater = described_class.new(
      stay: stay,
      draft: draft(booking_type: "rooms", room_ids: [@room_1.id], price_override_cents: 12_000),
      status: "confirmed", price_override_cents: 12_000, skip_availability: false
    )
    expect(updater.run).to be(true)
    # L'occupation reste intacte (pas d'auto-blocage → pas de perte de Reservation).
    expect(booking_of(stay.reload).reservations.map(&:room_id).uniq).to eq([@room_1.id])
  end

  it "refuse le passage en chambres seules sans chambre cochée" do
    stay = create_rooms_stay

    updater = described_class.new(
      stay: stay,
      draft: draft(booking_type: "rooms", room_ids: []),
      status: "confirmed"
    )
    expect(updater.run).to be(false)
    expect(updater.error_message).to include("au moins une chambre")
  end

  it "bloque le passage sur une chambre déjà prise par un AUTRE séjour confirmé" do
    # Un autre séjour confirmé occupe la chambre 3.
    Reservations::Builder.new(
      draft: draft(booking_type: "rooms", room_ids: [@room_3.id], email: "autre@example.com"),
      admin: true, status: "confirmed", source: "manual", price_override_cents: 5_000
    ).run!

    stay = create_rooms_stay(room_ids: [@room_1.id])
    updater = described_class.new(
      stay: stay,
      draft: draft(booking_type: "rooms", room_ids: [@room_3.id], price_override_cents: 12_000),
      status: "confirmed", price_override_cents: 12_000
    )
    expect(updater.run).to be(false)
    expect(updater.error_message).to include("plus disponibles")
  end

  # Revue Forge Phase 5.
  it "refuse des room_ids tous étrangers au gîte en édition (F1)" do
    foreign = Room.create!(name: "Chambre étrangère", level: 1)
    stay = create_rooms_stay
    updater = described_class.new(
      stay: stay,
      draft: draft(booking_type: "rooms", room_ids: [foreign.id], price_override_cents: 12_000),
      status: "confirmed", price_override_cents: 12_000
    )
    expect(updater.run).to be(false)
    expect(updater.error_message).to include("n'appartiennent pas")
  end

  it "n'auto-bloque pas la réédition d'un séjour GÎTE ENTIER confirmé (F4 — exclusion de soi en mode lodging)" do
    builder = Reservations::Builder.new(
      draft: draft, admin: true, status: "confirmed", source: "manual"
    )
    builder.run!
    stay = builder.stay

    updater = described_class.new(stay: stay, draft: draft, status: "confirmed")
    expect(updater.run).to be(true)
    expect(updater.availability_warning).to be_nil
  end
end
