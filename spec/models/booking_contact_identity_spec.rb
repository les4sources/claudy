require "rails_helper"

# Identité du réservataire (2026-09-16) : une ORGANISATION n'a ni prénom ni nom
# — elle se nomme par son groupe. Le prénom seul n'est donc plus obligatoire ;
# ce qui l'est, c'est de pouvoir NOMMER la réservation.
RSpec.describe "Identité du réservataire" do
  def booking_attrs(**overrides)
    {
      from_date: Date.today + 30,
      to_date: Date.today + 32,
      adults: 4,
      status: "pending"
    }.merge(overrides)
  end

  describe Booking do
    it "accepte une réservation nommée par son seul nom de groupe" do
      booking = Booking.new(booking_attrs(group_name: "École de Godinne"))

      expect(booking).to be_valid
      expect(booking.name).to eq("École de Godinne")
      expect(booking.greeting).to eq("Bonjour École de Godinne,")
    end

    it "accepte une réservation nommée par son seul prénom" do
      booking = Booking.new(booking_attrs(firstname: "Camille"))

      expect(booking).to be_valid
      expect(booking.name).to eq("Camille")
      expect(booking.greeting).to eq("Bonjour Camille,")
    end

    it "refuse une réservation sans prénom, sans nom et sans groupe" do
      booking = Booking.new(booking_attrs)

      expect(booking).not_to be_valid
      expect(booking.errors.full_messages.join(" ")).to match(/prénom, un nom ou un nom de groupe/)
    end
  end

  def space_attrs(**overrides)
    booking_attrs(**overrides).except(:adults)
  end

  describe SpaceBooking do
    it "accepte une réservation d'espace nommée par son seul nom de groupe" do
      space_booking = SpaceBooking.new(space_attrs(group_name: "École de Godinne"))

      expect(space_booking).to be_valid
      expect(space_booking.name).to eq("École de Godinne")
      expect(space_booking.greeting).to eq("Bonjour École de Godinne,")
    end

    it "refuse une réservation d'espace sans la moindre identité" do
      expect(SpaceBooking.new(space_attrs)).not_to be_valid
    end
  end
end
