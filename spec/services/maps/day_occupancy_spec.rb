require "rails_helper"

# Epic #348, phase 3 — la carte du jour. L'occupation se lit dans les
# `Reservation` de chambres (une ligne par nuit, nuits [arrivée, départ)) et
# dans les `SpaceReservation`, aux statuts bloquants — jamais dans
# `Booking.lodging_id` + dates.
RSpec.describe Maps::DayOccupancy do
  let(:today) { Date.new(2026, 10, 14) }
  let(:venues) { MapLayer.for_kind(:venues) }
  let(:square) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Mélisse", level: 1)
    lodging
  end
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }
  let!(:hulotte_feature) { venues.map_features.create!(geometry: square, linked_key: "Lodging:#{hulotte.id}") }
  let!(:salle_feature) { venues.map_features.create!(geometry: square, linked_key: "Space:#{grande_salle.id}") }

  def book(from:, to:, status: "confirmed", lodging: hulotte, name: "Martin")
    booking = Booking.new(lodging: lodging, from_date: from, to_date: to, status: status, lastname: name,
                          booking_type: "lodging", adults: 4, children: 2)
    booking.save!(validate: false)
    lodging.rooms.each do |room|
      (from...to).each { |night| Reservation.create!(booking: booking, room: room, date: night) }
    end
    booking
  end

  def book_space(date:, status: "confirmed", space: grande_salle, duration: "day")
    space_booking = SpaceBooking.new(from_date: date, to_date: date, status: status, lastname: "Salle")
    space_booking.save!(validate: false)
    SpaceReservation.create!(space_booking: space_booking, space: space, date: date, duration: duration)
    space_booking
  end

  def state_of(feature, date = today)
    described_class.new(date).states.fetch(feature.id)[:state]
  end

  it "un gîte sans réservation est libre" do
    expect(state_of(hulotte_feature)).to eq("free")
  end

  it "un gîte où l'on dort cette nuit est occupé" do
    book(from: today - 2, to: today + 2)
    expect(state_of(hulotte_feature)).to eq("occupied")
  end

  it "un jour d'arrivée ou de départ est un jour de rotation" do
    book(from: today, to: today + 2)
    expect(described_class.new(today).states[hulotte_feature.id]).to eq(state: "turnover", label: "Arrivée")

    # Le jour du départ, il n'y a plus de nuit datée de ce jour : la dernière
    # est celle de la veille. Le gîte est pourtant à préparer.
    expect(described_class.new(today + 2).states[hulotte_feature.id]).to eq(state: "turnover", label: "Départ")
  end

  it "départ le matin et arrivée le soir : les deux groupes, le partant d'abord" do
    leaving = book(from: today - 3, to: today, name: "Partant")
    arriving = book(from: today, to: today + 1, name: "Arrivant")

    expect(described_class.new(today).states[hulotte_feature.id][:label]).to eq("Arrivée et départ")
    groups = described_class.new(today).lodging_groups(hulotte)
    expect(groups.map(&:booking)).to eq([leaving, arriving])
    expect(groups.map(&:departing)).to eq([true, false])
    expect(groups.map(&:arriving)).to eq([false, true])
  end

  it "compte le pré-confirmé, comme le calendrier et le veto" do
    book(from: today - 1, to: today + 1, status: "pre_confirmed")
    expect(state_of(hulotte_feature)).to eq("occupied")
  end

  it "ignore les réservations en attente, annulées ou supprimées" do
    book(from: today - 1, to: today + 1, status: "pending")
    book(from: today - 1, to: today + 1, status: "canceled")
    book(from: today - 1, to: today + 1).soft_delete!(validate: false)
    expect(state_of(hulotte_feature)).to eq("free")
  end

  it "ne lit jamais Booking.lodging_id + dates sans réservation de chambre" do
    ghost = Booking.new(lodging: hulotte, from_date: today - 1, to_date: today + 1, status: "confirmed", lastname: "Fantôme")
    ghost.save!(validate: false)
    expect(state_of(hulotte_feature)).to eq("free")
  end

  it "donne le prochain séjour d'un gîte libre" do
    upcoming = book(from: today + 5, to: today + 7)
    book(from: today + 10, to: today + 12)
    expect(described_class.new(today).next_lodging_booking(hulotte)).to eq(upcoming)
  end

  it "une salle réservée ce jour est occupée, avec sa réservation" do
    space_booking = book_space(date: today)
    expect(state_of(salle_feature)).to eq("occupied")
    expect(described_class.new(today).space_groups(grande_salle).map(&:space_booking)).to eq([space_booking])
    expect(state_of(salle_feature, today + 1)).to eq("free")
    expect(described_class.new(today + 1).next_space_booking(grande_salle)).to be_nil
  end

  it "un espace partagé affiche le nombre de groupes" do
    bois = Space.create!(name: "Bois", capacity: 3)
    feature = venues.map_features.create!(geometry: square, linked_key: "Space:#{bois.id}")
    book_space(date: today, space: bois)
    expect(described_class.new(today).states[feature.id]).to eq(state: "occupied", label: "Occupé (1/3 groupes)")
  end

  it "n'interroge pas la base une fois par gîte" do
    5.times do |i|
      lodging = Lodging.create!(name: "Gîte #{i}", price_night_cents: 10_000)
      lodging.rooms << Room.create!(name: "Chambre #{i}", level: 1)
      venues.map_features.create!(geometry: square, linked_key: "Lodging:#{lodging.id}")
    end
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.new(today).states }
    expect(queries).to be <= 6
  end
end
