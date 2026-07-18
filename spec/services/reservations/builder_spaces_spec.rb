require "rails_helper"

# Epic #66, Phase 2 — Espaces dans la composition du séjour. Le Builder persiste
# désormais les espaces choisis (halls / space_slots) en un SpaceBooking +
# StayItem, y compris pour un séjour « espaces seuls » (sans hébergement). La part
# espaces vit sur le SpaceBooking ; l'hébergement porte le reste (aucun double-compte).
RSpec.describe Reservations::Builder, "espaces (epic #66, Phase 2)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end
  # Grande Salle → grande_salle (grille de pricing). Capacity 1 = salle exclusive.
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }
  # grande_salle / journée (barème semaine des salles) = 290 €.
  let(:grande_salle_journee_cents) { 29_000 }
  let(:hulotte_two_nights_cents)   { 74_500 }

  def draft(**overrides)
    Reservations::Draft.new({
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233"
    }.merge(overrides))
  end

  def hall(date: nil, kind: "grande_salle", period: "journee")
    { kind: kind, date: (date || arrival).iso8601, period: period }
  end

  describe "hébergement + espace" do
    it "crée un SpaceBooking + StayItem et ventile le prix sans double-compte" do
      builder = described_class.new(draft: draft(halls: [hall]), admin: true, source: "manual")
      expect(builder.run).to be(true)

      sb = builder.space_booking
      expect(sb).to be_persisted
      expect(builder.stay.stay_items.map(&:bookable)).to include(sb)
      expect(sb.space_reservations.map(&:space)).to eq([grande_salle])
      expect(sb.price_cents).to eq(grande_salle_journee_cents)

      # Le Booking d'hébergement porte le reste (hors espaces) — pas de double-compte.
      expect(builder.booking.price_cents).to eq(hulotte_two_nights_cents)
      # Total prévu = hébergement + espace.
      expect(builder.stay.total_amount_cents).to eq(hulotte_two_nights_cents + grande_salle_journee_cents)
      # recompute redonne exactement le même total (Booking + SpaceBooking).
      builder.stay.recompute_aggregates!
      expect(builder.stay.reload.total_amount_cents).to eq(hulotte_two_nights_cents + grande_salle_journee_cents)
    end
  end

  describe "séjour « espaces seuls » (sans hébergement)" do
    let(:spaces_only) { draft(lodging_id: nil, halls: [hall]) }

    it "ne crée AUCUN Booking mais persiste le SpaceBooking en StayItem" do
      builder = described_class.new(draft: spaces_only, admin: true, source: "manual")
      expect(builder.run).to be(true)

      expect(builder.booking).to be_nil
      sb = builder.space_booking
      expect(sb).to be_persisted
      expect(builder.stay.stay_items.map(&:bookable)).to eq([sb])
      expect(builder.stay.total_amount_cents).to eq(grande_salle_journee_cents)
      expect(builder.stay.arrival_date).to eq(arrival)
      expect(builder.stay.departure_date).to eq(departure)
    end

    it "garde des agrégats corrects après recompute (dates non écrasées à nil)" do
      builder = described_class.new(draft: spaces_only, admin: true, source: "manual")
      builder.run
      stay = builder.stay

      stay.recompute_aggregates!
      stay.reload
      expect(stay.total_amount_cents).to eq(grande_salle_journee_cents)
      expect(stay.arrival_date).to eq(arrival)
      expect(stay.departure_date).to eq(departure)
    end
  end

  describe "disponibilité capacity-aware des espaces" do
    def occupy_grande_salle!(date)
      sb = SpaceBooking.create!(firstname: "Occ", from_date: date, to_date: date, status: "confirmed")
      sb.space_reservations.create!(space: grande_salle, date: date, duration: "journee")
    end

    it "bloque un espace déjà complet hors force" do
      occupy_grande_salle!(arrival)
      builder = described_class.new(draft: draft(lodging_id: nil, halls: [hall]), admin: true, source: "manual")

      expect(builder.run).to be(false)
      expect(builder.error_message).to match(/complet/i)
      expect(Stay.count).to eq(0)
    end

    it "force la création avec un avertissement" do
      occupy_grande_salle!(arrival)
      builder = described_class.new(
        draft: draft(lodging_id: nil, halls: [hall]), admin: true, source: "manual", skip_availability: true
      )

      expect(builder.run).to be(true)
      expect(builder.availability_warning).to match(/forçant la disponibilité/i)
      expect(builder.space_booking).to be_persisted
    end
  end
end
