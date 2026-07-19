require "rails_helper"

# Couvre l'AC3 de la Phase 1 (epic #81) AU POINT D'ENTRÉE réel du canal admin :
# SpaceBookings::CreateService#run. Tout SpaceBooking créé ici doit repartir avec
# un Stay et un Customer upserté par email — comme le canal Booking.
RSpec.describe SpaceBookings::CreateService do
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }

  def params(overrides = {})
    ActionController::Parameters.new(
      space_booking: {
        firstname: "Nadia",
        lastname: "Bianchi",
        email: "Nadia@Example.com",
        from_date: Date.today + 30,
        to_date: Date.today + 33,
        duration: "journee",
        price: "300",
        status: "pending",
        space_ids: [grande_salle.id]
      }.merge(overrides)
    )
  end

  it "crée un SpaceBooking ET son Stay + Customer (canal admin)" do
    service = described_class.new

    expect(service.run(params)).to be(true)

    space_booking = service.space_booking.reload
    expect(space_booking.stay).to be_present
    expect(space_booking.stay.customer.email).to eq("nadia@example.com")
    expect(space_booking.stay.source).to eq("manual")
  end

  it "upserte le même Customer pour deux space_bookings au même email" do
    described_class.new.tap { |s| s.run(params(email: "repeat@example.com")) }
    described_class.new.tap do |s|
      s.run(params(email: "repeat@example.com", from_date: Date.today + 60, to_date: Date.today + 62))
    end

    expect(Customer.where(email: "repeat@example.com").count).to eq(1)
  end
end
