require "rails_helper"

RSpec.describe Stays::MergeOriginNotes do
  def build_booking(**attrs)
    Booking.create!({
      firstname: "Zoé",
      lastname: "Durand",
      email: "zoe@example.com",
      from_date: Date.new(2026, 8, 1),
      to_date: Date.new(2026, 8, 4),
      adults: 2,
      status: "confirmed",
      price_cents: 30_000
    }.merge(attrs))
  end

  def build_stay(notes: nil, bookables: [])
    customer = Customer.create!(email: "zoe@example.com", customer_type: "individual")
    stay = Stay.create!(customer: customer, notes: notes,
                        arrival_date: Date.new(2026, 8, 1), departure_date: Date.new(2026, 8, 4))
    bookables.each { |b| stay.stay_items.create!(bookable: b) }
    stay
  end

  describe "rapatriement" do
    it "recopie la note de la réservation dans un séjour qui n'en a pas" do
      stay = build_stay(bookables: [build_booking(notes: "Arrivée tardive, prévoir les clés.")])

      expect(described_class.call(stay)).to be(true)
      expect(stay.reload.notes).to eq("Arrivée tardive, prévoir les clés.")
    end

    it "ajoute la note d'origine SOUS celle du séjour, sans l'écraser" do
      stay = build_stay(notes: "Vu avec Malau.", bookables: [build_booking(notes: "Sans gluten.")])

      described_class.call(stay)

      expect(stay.reload.notes).to eq("Vu avec Malau.\n\nSans gluten.")
    end

    it "ne touche JAMAIS à la note portée par la réservation" do
      booking = build_booking(notes: "Sans gluten.")
      stay = build_stay(bookables: [booking])

      described_class.call(stay)

      expect(booking.reload.notes).to eq("Sans gluten.")
    end

    it "réunit les notes de plusieurs réservations d'un même séjour" do
      space = SpaceBooking.create!(firstname: "Zoé", lastname: "Durand", email: "ciep@example.com",
                                   from_date: Date.new(2026, 8, 1), to_date: Date.new(2026, 8, 4),
                                   status: "confirmed", notes: "Buffet végétarien.")
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten."), space])

      described_class.call(stay)

      expect(stay.reload.notes).to eq("Sans gluten.\n\nBuffet végétarien.")
    end

    it "ne garde qu'un exemplaire d'une note saisie à l'identique sur deux réservations" do
      space = SpaceBooking.create!(firstname: "Zoé", lastname: "Durand", email: "ciep@example.com",
                                   from_date: Date.new(2026, 8, 1), to_date: Date.new(2026, 8, 4),
                                   status: "confirmed", notes: "Sans gluten.")
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten."), space])

      described_class.call(stay)

      expect(stay.reload.notes).to eq("Sans gluten.")
    end
  end

  describe "idempotence" do
    it "ne recopie rien une deuxième fois" do
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten.")])
      described_class.call(stay)

      expect(described_class.call(stay)).to be(false)
      expect(stay.reload.notes).to eq("Sans gluten.")
    end

    it "reconnaît une note déjà recopiée à la main, à la mise en forme près" do
      stay = build_stay(notes: "Sans   gluten.", bookables: [build_booking(notes: "sans gluten.")])

      expect(described_class.call(stay)).to be(false)
      expect(stay.reload.notes).to eq("Sans   gluten.")
    end

    it "laisse intact un séjour sans aucune note" do
      stay = build_stay(bookables: [build_booking(notes: nil)])

      expect(described_class.call(stay)).to be(false)
      expect(stay.reload.notes.to_s).to eq("")
    end

    it "n'écrit pas dans updated_at — le rapatriement n'est pas une modification éditoriale" do
      stay = build_stay(bookables: [build_booking(notes: "Sans gluten.")])

      expect { described_class.call(stay) }.not_to change { stay.reload.updated_at }
    end
  end
end
