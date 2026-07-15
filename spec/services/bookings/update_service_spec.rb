require "rails_helper"

# Couvre le durcissement de la Phase 3 (epic #26) sur Bookings::UpdateService :
# éditer un Booking legacy dépourvu de Stay doit désormais lui en créer un
# (idempotent — pas de second Stay si un vivant existe déjà).
RSpec.describe Bookings::UpdateService do
  let(:lodging) do
    l = Lodging.create!(name: "Gîte Update", available_for_bookings: true, price_night: 100)
    l.rooms << Room.create!(code: "UPD", name: "Update")
    l
  end

  def stayless_booking
    # Création directe, SANS EnsureForBooking : reproduit un booking legacy d'avant
    # le backfill (aucun Stay rattaché).
    Booking.create!(
      firstname: "Léa",
      lastname: "Petit",
      email: "lea@example.com",
      booking_type: "lodging",
      lodging_id: lodging.id,
      from_date: Date.today + 40,
      to_date: Date.today + 43,
      adults: 2,
      status: "pending",
      price_cents: 30_000
    )
  end

  def update_params(booking, overrides = {})
    ActionController::Parameters.new(
      booking: {
        firstname: booking.firstname,
        lastname: booking.lastname,
        email: booking.email,
        booking_type: "lodging",
        lodging_id: lodging.id,
        from_date: booking.from_date,
        to_date: booking.to_date,
        adults: booking.adults,
        status: "pending",
        price: "300"
      }.merge(overrides)
    )
  end

  it "crée un Stay pour un Booking legacy qui n'en avait pas" do
    booking = stayless_booking
    expect(booking.stay).to be_nil

    service = described_class.new(booking_id: booking.id)
    expect(service.run(update_params(booking))).to be(true)

    expect(booking.reload.stay).to be_present
  end

  it "est idempotent : éditer un booking déjà rattaché ne crée pas de second Stay" do
    booking = stayless_booking
    Stays::EnsureForBooking.call(booking)

    service = described_class.new(booking_id: booking.id)
    expect { service.run(update_params(booking)) }.not_to change(Stay, :count)

    expect(StayItem.where(bookable: booking.reload).count).to eq(1)
  end
end
