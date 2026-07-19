require "rails_helper"

# Epic #81, Phase 5 — le Builder sait réserver des CHAMBRES SEULES dans un séjour
# (parité avec le canal Booking direct, DANS le séjour). Mode "rooms" : on
# construit les Reservation UNIQUEMENT pour les chambres cochées ; la dispo se
# vérifie sur ces chambres ; le veto joue dans les deux sens.
RSpec.describe Reservations::Builder, "chambres seules (epic #81, Phase 5)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << (@room_1 = Room.create!(name: "Chambre 1", level: 1))
    lodging.rooms << (@room_2 = Room.create!(name: "Chambre 2", level: 1))
    lodging.rooms << (@room_3 = Room.create!(name: "Chambre 3", level: 1))
    lodging
  end

  let(:arrival)   { Date.today + 30 } # 2 nuits : [arrival, arrival+2)
  let(:departure) { Date.today + 32 }

  def draft(**overrides)
    Reservations::Draft.new({
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601,
      departure_date: departure.iso8601,
      dogs_count: 0,
      first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233"
    }.merge(overrides))
  end

  describe "création d'une occupation chambres seules" do
    it "route booking_type=rooms et ne réserve QUE les chambres cochées" do
      builder = described_class.new(
        draft: draft(booking_type: "rooms", room_ids: [@room_1.id, @room_2.id]),
        admin: true, status: "confirmed", source: "manual"
      )
      expect(builder.run!).to be(true)

      booking = builder.booking
      expect(booking.booking_type).to eq("rooms")
      expect(booking.lodging_id).to eq(hulotte.id) # référence gîte conservée
      # 2 chambres × 2 nuits = 4 Reservation, uniquement sur les chambres cochées.
      expect(booking.reservations.count).to eq(4)
      expect(booking.reservations.map(&:room_id).uniq).to match_array([@room_1.id, @room_2.id])
      expect(booking.reservations.map(&:room_id)).not_to include(@room_3.id)
    end

    it "n'applique aucun forfait gîte au Booking (prix piloté par l'override)" do
      builder = described_class.new(
        draft: draft(booking_type: "rooms", room_ids: [@room_1.id]),
        admin: true, status: "confirmed", source: "manual"
      )
      builder.run!
      expect(builder.booking.price_cents).to eq(0)
      expect(builder.stay.total_amount_cents).to eq(0)
    end

    it "honore le prix imposé en mode chambres" do
      builder = described_class.new(
        draft: draft(booking_type: "rooms", room_ids: [@room_1.id]),
        admin: true, status: "confirmed", source: "manual",
        price_override_cents: 12_000
      )
      builder.run!
      expect(builder.stay.total_amount_cents).to eq(12_000)
    end

    it "borne les chambres au gîte (une chambre d'un autre gîte est ignorée)" do
      other = Lodging.create!(name: "La Chevêche", price_night_cents: 27_500)
      other.rooms << (foreign = Room.create!(name: "Chevêche 1", level: 1))

      builder = described_class.new(
        draft: draft(booking_type: "rooms", room_ids: [@room_1.id, foreign.id]),
        admin: true, status: "confirmed", source: "manual"
      )
      builder.run!
      expect(builder.booking.reservations.map(&:room_id).uniq).to eq([@room_1.id])
    end

    it "refuse une création chambres seules sans aucune chambre cochée" do
      builder = described_class.new(
        draft: draft(booking_type: "rooms", room_ids: []),
        admin: true, status: "confirmed", source: "manual"
      )
      expect(builder.run).to be(false)
      expect(builder.error_message).to include("au moins une chambre")
    end
  end

  describe "veto croisé gîte entier ↔ chambre" do
    it "une chambre confirmée rend le gîte ENTIER indisponible, l'autre chambre restant libre" do
      described_class.new(
        draft: draft(booking_type: "rooms", room_ids: [@room_1.id]),
        admin: true, status: "confirmed", source: "manual"
      ).run!

      # Le gîte entier ne peut plus être réservé (une de ses chambres est prise).
      expect(hulotte.available_between?(arrival, departure)).to be(false)
      # Mais une AUTRE chambre du gîte reste réservable.
      expect(hulotte.rooms_available_between?([@room_2.id], arrival, departure)).to be(true)
      expect(hulotte.rooms_available_between?([@room_1.id], arrival, departure)).to be(false)
    end

    it "un gîte entier confirmé bloque une nouvelle résa chambres seules (sans forçage)" do
      # Occupation gîte entier confirmée.
      described_class.new(draft: draft, admin: true, status: "confirmed", source: "manual").run!

      # Tentative chambres seules sur une chambre du gîte → indispo → refus.
      rooms_builder = described_class.new(
        draft: draft(booking_type: "rooms", room_ids: [@room_2.id], email: "autre@example.com"),
        admin: true, status: "confirmed", source: "manual"
      )
      expect(rooms_builder.run).to be(false)
      expect(rooms_builder.error_message).to include("plus disponibles")
    end

    it "permet de forcer la dispo en mode chambres (surbooking) avec avertissement" do
      described_class.new(draft: draft, admin: true, status: "confirmed", source: "manual").run!

      forced = described_class.new(
        draft: draft(booking_type: "rooms", room_ids: [@room_2.id], email: "autre@example.com"),
        admin: true, status: "confirmed", source: "manual", skip_availability: true
      )
      expect(forced.run!).to be(true)
      expect(forced.availability_warning).to include("forçant la disponibilité")
    end
  end

  describe "garde-fous de revue (Forge Phase 5)" do
    it "refuse des room_ids tous étrangers au gîte — jamais d'occupation fantôme (F1)" do
      foreign = Room.create!(name: "Chambre étrangère", level: 1)
      builder = described_class.new(
        draft: draft(booking_type: "rooms", room_ids: [foreign.id]),
        admin: true, status: "confirmed", source: "manual"
      )
      expect(builder.run).to be(false)
      expect(builder.error_message).to include("n'appartiennent pas")
      expect(Booking.count).to eq(0)
    end

    it "persiste booking_type sur le Booking créé (F2 — plus de dérivation fragile)" do
      described_class.new(
        draft: draft(booking_type: "rooms", room_ids: [@room_1.id, @room_2.id]),
        admin: true, status: "confirmed", source: "manual"
      ).run!
      expect(Booking.last.read_attribute(:booking_type)).to eq("rooms")

      described_class.new(
        draft: draft(email: "entier@example.com", arrival_date: (departure + 1).iso8601, departure_date: (departure + 3).iso8601),
        admin: true, status: "confirmed", source: "manual"
      ).run!
      expect(Booking.last.read_attribute(:booking_type)).to eq("lodging")
    end
  end
end
