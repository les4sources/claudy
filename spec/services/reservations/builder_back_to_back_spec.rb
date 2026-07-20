require "rails_helper"

# Issue #94 — bout en bout : deux séjours dos-à-dos doivent être créables via
# `Reservations::Builder` SANS forçage de disponibilité. Le sur-blocage au jour de
# rotation refusait/avertissait à tort le second séjour quand son jour de départ
# (ou d'arrivée) coïncidait avec la rotation d'un séjour confirmé voisin.
RSpec.describe Reservations::Builder, "rotation dos-à-dos (issue #94)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  # Séjour existant B[+32 → +34] confirmé : occupe les NUITS +32 et +33.
  let(:later_from) { Date.today + 32 }
  let(:later_to)   { Date.today + 34 }
  before do
    occ = Booking.create!(firstname: "Occ", from_date: later_from, to_date: later_to, adults: 1, status: "confirmed", lodging: hulotte)
    (later_from...later_to).each { |d| Reservation.create!(booking: occ, room: hulotte.rooms.first, date: d) }
  end

  # Nouveau séjour A[+30 → +32] : son jour de départ (+32) = arrivée de B.
  def draft(**overrides)
    Reservations::Draft.new({
      lodging_id: hulotte.id,
      arrival_date: (Date.today + 30).iso8601,
      departure_date: (Date.today + 32).iso8601,
      dogs_count: 0,
      first_name: "Camille",
      last_name: "Martin",
      email: "camille@example.com",
      phone: "+32470112233"
    }.merge(overrides))
  end

  it "crée le séjour dos-à-dos sans forçage ni avertissement de disponibilité" do
    builder = described_class.new(draft: draft)

    expect(builder.run).to be(true)
    expect(builder.availability_warning).to be_blank
    expect(builder.stay).to be_persisted
    expect(builder.booking.lodging_id).to eq(hulotte.id)
  end
end
