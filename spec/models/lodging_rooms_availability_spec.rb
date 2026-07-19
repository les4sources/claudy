require "rails_helper"

# Epic #81, Phase 5 — dispo « chambres seules » (`Lodging#rooms_available_between?`).
# Réserver un SOUS-ENSEMBLE de chambres se vérifie sur CES chambres, pas sur tout
# le gîte, tout en gardant l'entanglement Grand-Duc (chambres partagées) cohérent.
RSpec.describe Lodging, "#rooms_available_between? (epic #81, Phase 5)", type: :model do
  let(:grand_duc) { Lodging.create!(name: "Le Grand-Duc", price_night_cents: 12_000) }
  let(:hulotte)   { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }
  let(:cheveche)  { Lodging.create!(name: "La Chevêche", price_night_cents: 8_000) }

  let(:hulotte_1) { Room.create!(name: "Hulotte 1", level: 1) }
  let(:hulotte_2) { Room.create!(name: "Hulotte 2", level: 1) }
  let(:cheveche_1) { Room.create!(name: "Chevêche 1", level: 1) }

  let(:from) { Date.new(2026, 8, 1) }
  let(:to)   { Date.new(2026, 8, 3) }

  before do
    LodgingComposition.create!(composite_lodging: grand_duc, component_lodging: hulotte)
    LodgingComposition.create!(composite_lodging: grand_duc, component_lodging: cheveche)
    hulotte.rooms << hulotte_1
    hulotte.rooms << hulotte_2
    cheveche.rooms << cheveche_1
    # Le composite possède l'union des chambres des composants.
    grand_duc.rooms << hulotte_1
    grand_duc.rooms << hulotte_2
    grand_duc.rooms << cheveche_1
  end

  # Réserve (confirmé) une chambre précise sur la fenêtre.
  def reserve_room(room, from:, to:)
    booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to, adults: 1, status: "confirmed", lodging: hulotte)
    (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    booking
  end

  it "reste dispo quand aucune des chambres visées n'est prise" do
    expect(hulotte.rooms_available_between?([hulotte_1.id, hulotte_2.id], from, to)).to be(true)
  end

  it "devient indispo dès qu'UNE chambre visée est prise (confirmée)" do
    reserve_room(hulotte_1, from: from, to: to)
    expect(hulotte.rooms_available_between?([hulotte_1.id], from, to)).to be(false)
    # …mais l'autre chambre du même gîte reste libre (granularité chambre).
    expect(hulotte.rooms_available_between?([hulotte_2.id], from, to)).to be(true)
  end

  it "borne les room_ids aux chambres du gîte (anti-injection cross-gîte)" do
    # La chambre de la Chevêche n'appartient pas à La Hulotte → ignorée.
    reserve_room(cheveche_1, from: from, to: to) # confirmé sur la chambre Chevêche
    expect(hulotte.rooms_available_between?([cheveche_1.id], from, to)).to be(true)
  end

  it "retombe sur la dispo du gîte entier sans room_ids exploitables" do
    reserve_room(hulotte_1, from: from, to: to)
    expect(hulotte.rooms_available_between?([], from, to)).to be(false)
  end

  it "respecte une indisponibilité posée sur le gîte" do
    Unavailability.create!(lodging: hulotte, date: from)
    expect(hulotte.rooms_available_between?([hulotte_2.id], from, to)).to be(false)
  end

  describe "entanglement Grand-Duc (chambres partagées)" do
    it "réserver une chambre de la Hulotte bloque le composite mais pas la Chevêche" do
      reserve_room(hulotte_1, from: from, to: to)
      # Le composite partage la chambre Hulotte → indisponible en gîte entier.
      expect(grand_duc.available_between?(from, to)).to be(false)
      # La Chevêche ne partage pas cette chambre → toujours dispo.
      expect(cheveche.available_between?(from, to)).to be(true)
      # …et ses propres chambres restent réservables en mode chambres.
      expect(cheveche.rooms_available_between?([cheveche_1.id], from, to)).to be(true)
    end
  end
end
