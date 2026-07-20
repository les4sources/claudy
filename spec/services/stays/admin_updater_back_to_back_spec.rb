require "rails_helper"

# Issue #94 (revue Forge F2) — le veto d'ÉDITION (`AdminUpdater#lodging_available?`)
# duplique la requête de nuits au lieu de déléguer à Lodging : on couvre donc SES
# deux sens à lui. (a) Permissif : rééditer un séjour dos-à-dos d'un voisin
# confirmé passe sans forçage. (b) Bloquant : le faire chevaucher réellement le
# voisin est refusé — un veto cassé « toujours oui » serait attrapé ici.
RSpec.describe Stays::AdminUpdater, "rotation dos-à-dos en édition (issue #94)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  # Voisin confirmé B[+32 → +34] : occupe les NUITS +32 et +33.
  let(:neighbor_from) { Date.today + 32 }
  before do
    occ = Booking.create!(firstname: "Occ", from_date: neighbor_from, to_date: neighbor_from + 2,
                          adults: 1, status: "confirmed", lodging: hulotte)
    (neighbor_from...(neighbor_from + 2)).each { |d| Reservation.create!(booking: occ, room: hulotte.rooms.first, date: d) }
  end

  def draft(arrival:, departure:)
    Reservations::Draft.new(
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille-edit@example.com", phone: "+32470112233"
    )
  end

  # Séjour à éditer A[+30 → +32] : départ = arrivée du voisin (dos-à-dos).
  let(:stay) do
    builder = Reservations::Builder.new(
      draft: draft(arrival: Date.today + 30, departure: Date.today + 32),
      admin: true, status: "confirmed", source: "manual"
    )
    builder.run!
    builder.stay
  end

  it "réédite un séjour dos-à-dos du voisin sans forçage ni avertissement" do
    updater = described_class.new(
      stay: stay,
      draft: draft(arrival: Date.today + 30, departure: Date.today + 32),
      status: "confirmed"
    )

    expect(updater.run).to be(true)
    expect(updater.availability_warning).to be_blank
  end

  it "refuse une édition qui chevauche RÉELLEMENT le voisin (nuit +32 commune)" do
    updater = described_class.new(
      stay: stay,
      draft: draft(arrival: Date.today + 31, departure: Date.today + 33),
      status: "confirmed"
    )

    expect(updater.run).to be(false)
    expect(updater.error_message).to include("plus disponibles")
  end
end
