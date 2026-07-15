require "rails_helper"

# Couvre le durcissement de la Phase 3 (epic #26) sur le funnel PUBLIC legacy
# (POST /public/bookings), encore vivant : tout Booking créé ici doit lui aussi
# repartir avec un Stay + un Customer, comme le canal admin/OTA — sinon l'invariant
# global « 0 Booking sans Stay » se casse pour les nouvelles résas publiques.
RSpec.describe Public::Bookings::CreateService do
  let(:lodging) do
    l = Lodging.create!(name: "Gîte Public", available_for_bookings: true, price_night: 100)
    l.rooms << Room.create!(code: "PUB", name: "Public")
    l
  end

  def params(overrides = {})
    ActionController::Parameters.new(
      booking: {
        firstname: "Camille",
        lastname: "Martin",
        email: "Camille@Example.com",
        booking_type: "lodging",
        lodging_id: lodging.id,
        from_date: Date.today + 30,
        to_date: Date.today + 33,
        adults: 2,
        shown_price_cents: 30_000,
        terms_approval: "1"
      }.merge(overrides)
    )
  end

  it "crée le Booking ET son Stay + Customer (source manual, plateforme web)" do
    service = described_class.new

    expect(service.run(params)).to be(true)

    booking = service.booking.reload
    expect(booking.platform).to eq("web")
    expect(booking.stay).to be_present
    expect(booking.stay.source).to eq("manual")
    expect(booking.stay.customer.email).to eq("camille@example.com")
  end

  it "reste idempotent : un Booking public ne porte qu'un seul StayItem vivant" do
    service = described_class.new
    service.run(params(email: "unique@example.com"))

    booking = service.booking.reload
    expect(StayItem.where(bookable: booking).count).to eq(1)
  end

  it "n'expose aucun payments_attributes : public_booking_params ne le permet pas" do
    service = described_class.new

    expect do
      service.run(params(payments_attributes: [{ amount: "80", payment_method: "cash" }]))
    end.not_to change(Payment, :count)

    expect(service.booking.reload.payments).to be_empty
  end
end
