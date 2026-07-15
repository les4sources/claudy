require "rails_helper"

RSpec.describe Reservations::Builder do
  # Hébergement réservable avec une chambre, pour que available_between? réponde
  # vrai sur la fenêtre choisie.
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    room = Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << room
    lodging
  end

  let(:arrival) { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def draft(**overrides)
    Reservations::Draft.new({
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601,
      departure_date: departure.iso8601,
      dogs_count: 0,
      first_name: "Camille",
      last_name: "Martin",
      email: "Camille@Example.com",
      phone: "+32470112233"
    }.merge(overrides))
  end

  # ------------------------------------------------------------------------
  # Epic #26, Phase 2 — Stay-first : le Booking redevient une simple OCCUPATION
  # d'hébergement. Un séjour sans hébergement ne crée plus de « Booking fantôme »,
  # et le paiement est rattaché au Stay dans tous les cas.
  # ------------------------------------------------------------------------
  describe "#run — Stay-first (epic #26)" do
    context "séjour AVEC hébergement" do
      it "crée un Booking d'occupation (le calendrier reste bloqué) et rattache le paiement au Stay" do
        builder = described_class.new(draft: draft)
        expect(builder.run).to be(true)

        expect(builder.booking).to be_persisted
        expect(builder.booking.lodging_id).to eq(hulotte.id)
        expect(builder.stay.stay_items.map(&:bookable)).to include(builder.booking)
        expect(builder.payment.stay).to eq(builder.stay)
      end
    end

    context "séjour SANS hébergement (camping seul)" do
      let(:camping_draft) do
        draft(lodging_id: nil, per_night_resources: { "tente" => ["2", "2"] })
      end

      it "ne crée AUCUN Booking" do
        builder = described_class.new(draft: camping_draft)
        expect(builder.run).to be(true)

        expect(builder.booking).to be_nil
        expect(builder.stay.stay_items).to be_empty
        expect(builder.stay.bookables).to be_empty
      end

      it "rattache quand même le paiement au Stay" do
        builder = described_class.new(draft: camping_draft)
        builder.run

        expect(builder.payment).to be_persisted
        expect(builder.payment.booking).to be_nil
        expect(builder.payment.stay).to eq(builder.stay)
        expect(builder.stay.payments).to include(builder.payment)
      end
    end

    context "séjour vide (ni hébergement ni emplacement)" do
      it "est refusé" do
        builder = described_class.new(draft: draft(lodging_id: nil))

        expect(builder.run).to be(false)
        expect(builder.error_message).to match(/hébergement ou un emplacement/i)
      end
    end
  end

  describe "#run (succès)" do
    it "crée un Stay pending source=reservation (PAS d'auto-confirm — Q5/AC-T2-19)" do
      builder = described_class.new(draft: draft)
      expect(builder.run).to be(true)

      stay = builder.stay
      expect(stay.status).to eq("pending")
      expect(stay.source).to eq("reservation")
      expect(stay.source).not_to eq(stay.legacy_origin) # distinct (AC-T2-22b)
    end

    it "upsert le Customer par email lowercase (AC-T2-18)" do
      described_class.new(draft: draft).run
      described_class.new(draft: draft(first_name: "Cam")).run

      customers = Customer.where(email: "camille@example.com")
      expect(customers.count).to eq(1)
      expect(customers.first.stays.count).to eq(2)
    end

    it "crée un Booking item + un Payment pending = acompte 50 % (réutilise l'infra Stripe)" do
      builder = described_class.new(draft: draft)
      builder.run

      expect(builder.booking).to be_persisted
      expect(builder.stay.stay_items.map(&:bookable)).to include(builder.booking)
      expect(builder.payment.status).to eq("pending")
      # Hulotte 2 nuits = 485 + 260 = 745 € ; acompte 50 % = 372,50 €.
      expect(builder.payment.amount_cents).to eq(37_250)
      # issue #26 : le Payment porte aussi le lien direct vers le Stay.
      expect(builder.payment.stay).to eq(builder.stay)
      expect(builder.stay.payments).to include(builder.payment)
    end
  end

  describe "supplément chien plafonné (Q2 — AC-T2-09b / AC-T2-15)" do
    it "facture un seul chien même si plusieurs demandés et consigne pour Malau" do
      one = described_class.new(draft: draft(dogs_count: 1)).tap(&:run).stay.total_amount_cents
      many_builder = described_class.new(draft: draft(dogs_count: 3))
      many_builder.run
      many = many_builder.stay.total_amount_cents

      expect(many).to eq(one)                       # pas de 3× 50 €
      expect(many_builder.multi_dogs?).to be(true)
      expect(many_builder.stay.notes).to match(/multi.?chiens/i)
    end
  end

  describe "#run (échecs — pas d'écriture)" do
    it "refuse sans email exploitable" do
      builder = described_class.new(draft: draft(email: ""))
      expect(builder.run).to be(false)
      expect(Stay.count).to eq(0)
      expect(builder.error_message).to include("email")
    end

    it "refuse des dates indisponibles" do
      # Occupe la Hulotte sur la fenêtre.
      occ = Booking.create!(firstname: "Occ", from_date: arrival, to_date: departure, adults: 1, status: "confirmed")
      (arrival..departure).each { |d| Reservation.create!(booking: occ, room: hulotte.rooms.first, date: d) }

      builder = described_class.new(draft: draft)
      expect(builder.run).to be(false)
      expect(builder.error_message).to include("disponibles")
      expect(Stay.count).to eq(0)
    end
  end
end
