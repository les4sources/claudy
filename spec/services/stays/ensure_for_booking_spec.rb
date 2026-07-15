require "rails_helper"

RSpec.describe Stays::EnsureForBooking do
  def build_booking(**attrs)
    Booking.create!({
      firstname: "Zoé",
      lastname: "Durand",
      email: "zoe@example.com",
      from_date: Date.new(2026, 8, 1),
      to_date: Date.new(2026, 8, 4),
      adults: 2,
      status: "pending",
      price_cents: 30_000
    }.merge(attrs))
  end

  describe "création d'un Stay pour un Booking qui n'en a pas" do
    it "crée le Stay, le StayItem et upserte le Customer par email" do
      booking = build_booking

      stay = described_class.call(booking)

      expect(stay).to be_persisted
      expect(booking.reload.stay).to eq(stay)
      expect(stay.customer.email).to eq("zoe@example.com")
      expect(stay.stay_items.map(&:bookable)).to contain_exactly(booking)
    end

    it "recopie dates, statut et montant depuis le booking sans le muter" do
      booking = build_booking

      expect { described_class.call(booking) }.not_to change { booking.reload.attributes }

      stay = booking.reload.stay
      expect(stay.arrival_date).to eq(Date.new(2026, 8, 1))
      expect(stay.departure_date).to eq(Date.new(2026, 8, 4))
      expect(stay.status).to eq("pending")
      expect(stay.total_amount_cents).to eq(30_000)
    end

    it "attribue source 'ota' pour une résa airbnb" do
      stay = described_class.call(build_booking(platform: "airbnb"))
      expect(stay.source).to eq("ota")
    end

    it "attribue source 'ota' pour une résa bookingdotcom" do
      stay = described_class.call(build_booking(platform: "bookingdotcom"))
      expect(stay.source).to eq("ota")
    end

    it "attribue source 'manual' pour une saisie admin classique" do
      stay = described_class.call(build_booking(platform: "web"))
      expect(stay.source).to eq("manual")
    end

    it "rattache un booking sans email exploitable au Customer fourre-tout" do
      stay = described_class.call(build_booking(email: nil))
      expect(stay.customer.catch_all?).to be(true)
    end

    it "crée un Customer organisation quand group_name est présent" do
      stay = described_class.call(build_booking(email: "asso@example.com", group_name: "Les Amis"))
      expect(stay.customer.customer_type).to eq("organization")
      expect(stay.customer.organization_name).to eq("Les Amis")
    end
  end

  describe "idempotence" do
    it "renvoie le Stay existant sans en créer un second" do
      booking = build_booking
      first = described_class.call(booking)

      second = nil
      expect { second = described_class.call(booking) }.not_to change(Stay, :count)
      expect(second).to eq(first)
      expect(StayItem.where(bookable: booking).count).to eq(1)
    end
  end

  # État latent (improbable mais possible) : un StayItem VIVANT pointant vers un
  # Stay soft-deleted. `booking.stay` (double scope vivant) vaut alors nil, donc
  # EnsureForBooking est rappelé. Sans le repoint, il créerait un 2e StayItem vivant
  # (unicité scoped sur stay_id ⇒ autorisé) et divergerait du compteur du backfill.
  describe "état latent : StayItem vivant → Stay soft-deleted" do
    def build_latent_state
      booking = build_booking(email: "latent@example.com")
      dead_stay = described_class.call(booking)
      dead_stay.soft_delete!(validate: false)
      # Le soft-delete du Stay cascade sur son StayItem : on le ressuscite pour
      # reconstruire l'état exact « StayItem vivant → Stay mort ».
      StayItem.with_deleted do
        StayItem.unscoped
          .find_by(bookable_id: booking.id, bookable_type: "Booking")
          .update_column(:deleted_at, nil)
      end
      [booking.reload, dead_stay]
    end

    it "repointe le StayItem orphelin au lieu d'en créer un second" do
      booking, dead_stay = build_latent_state
      expect(booking.stay).to be_nil
      expect(StayItem.where(bookable: booking).count).to eq(1)

      new_stay = described_class.call(booking)

      expect(StayItem.where(bookable: booking).count).to eq(1)
      expect(new_stay.id).not_to eq(dead_stay.id)
      expect(booking.reload.stay).to eq(new_stay)
    end
  end
end
