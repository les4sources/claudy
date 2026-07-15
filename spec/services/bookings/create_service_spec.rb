require "rails_helper"

# Couvre AC1 de la Phase 3 (epic #26) AU POINT D'ENTRÉE réel du canal admin/OTA :
# Bookings::CreateService#run. Tout Booking créé ici doit repartir avec un Stay
# et un Customer upserté par email — résas manuelles ET OTA (même formulaire,
# distinguées par `platform`).
RSpec.describe Bookings::CreateService do
  let(:lodging) do
    l = Lodging.create!(name: "Gîte Test", available_for_bookings: true, price_night: 100)
    room = Room.create!(code: "TST", name: "Test")
    l.rooms << room
    l
  end

  def params(overrides = {})
    ActionController::Parameters.new(
      booking: {
        firstname: "Nadia",
        lastname: "Bianchi",
        email: "Nadia@Example.com",
        booking_type: "lodging",
        lodging_id: lodging.id,
        from_date: Date.today + 30,
        to_date: Date.today + 33,
        adults: 2,
        price: "300",
        status: "pending",
        platform: "web"
      }.merge(overrides)
    )
  end

  it "crée un Booking ET son Stay + Customer (canal admin)" do
    service = described_class.new

    expect(service.run(params)).to be(true)

    booking = service.booking.reload
    expect(booking.stay).to be_present
    expect(booking.stay.customer.email).to eq("nadia@example.com")
    expect(booking.stay.source).to eq("manual")
  end

  it "attribue source 'ota' à une résa OTA (platform airbnb) via le même canal" do
    service = described_class.new

    expect(service.run(params(platform: "airbnb", email: "guest@guest.airbnb.com"))).to be(true)

    expect(service.booking.reload.stay.source).to eq("ota")
  end

  it "upserte le même Customer pour deux bookings au même email" do
    described_class.new.tap { |s| s.run(params(email: "repeat@example.com")) }
    described_class.new.tap { |s| s.run(params(email: "repeat@example.com", from_date: Date.today + 60, to_date: Date.today + 62)) }

    expect(Customer.where(email: "repeat@example.com").count).to eq(1)
  end

  # Trou fermé (epic #26, Phase 3) : `payments_attributes` n'est plus permis dans
  # booking_params. Une requête forgée qui nicherait un paiement ne doit créer AUCUN
  # Payment (sinon il serait sauvé sans stay_id, avant EnsureForBooking).
  it "ignore un payments_attributes forgé : aucun Payment n'est créé, le Stay l'est" do
    forged = params(payments_attributes: [{ amount: "150", payment_method: "cash" }])
    service = described_class.new

    expect { expect(service.run(forged)).to be(true) }.not_to change(Payment, :count)

    booking = service.booking.reload
    expect(booking.payments).to be_empty
    expect(booking.stay).to be_present
  end
end
