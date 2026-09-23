require "rails_helper"

# Grand-Duc, réveillon 2026 (séjour 1506) : passé en « confirmé » via le
# formulaire d'édition, le séjour gardait un Booking `pending`. Le veto de
# disponibilité — et donc le calendrier public — lit le statut du Booking : le
# gîte restait affiché LIBRE. L'édition doit propager le statut, sans email.
RSpec.describe Stays::AdminUpdater, "propagation du statut aux réservables" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500, available_for_bookings: true)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival) { Date.today + 40 }

  def draft
    Reservations::Draft.new(
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601, departure_date: (arrival + 3).iso8601,
      dogs_count: 0, first_name: "Simon", last_name: "Martin",
      email: "simon-propagation@example.com", phone: "+32470112233"
    )
  end

  let(:stay) do
    builder = Reservations::Builder.new(draft: draft, admin: true, status: "pending", source: "ota")
    builder.run!
    builder.stay
  end

  let(:booking) { stay.bookables.find { |b| b.is_a?(Booking) } }

  it "confirme le Booking quand l'admin confirme le séjour, et bloque le gîte" do
    expect(booking.status).to eq("pending")
    expect(hulotte.available_on?(arrival + 1)).to be(true)

    expect(described_class.new(stay: stay, draft: draft, status: "confirmed").run).to be(true)

    expect(booking.reload.status).to eq("confirmed")
    expect(hulotte.available_on?(arrival + 1)).to be(false)
  end

  it "n'envoie pas l'email client du Booking" do
    booking # séjour créé hors du bloc mesuré
    expect(BookingMailer).not_to receive(:booking_confirmed)

    expect(described_class.new(stay: stay, draft: draft, status: "confirmed").run).to be(true)
    expect(booking.reload.status).to eq("confirmed")
  end
end
