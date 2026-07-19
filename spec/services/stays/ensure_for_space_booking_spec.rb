require "rails_helper"

RSpec.describe Stays::EnsureForSpaceBooking do
  def build_space_booking(**attrs)
    SpaceBooking.create!({
      firstname: "Zoé",
      lastname: "Durand",
      email: "zoe@example.com",
      phone: "+32470112233",
      from_date: Date.new(2026, 8, 1),
      to_date: Date.new(2026, 8, 4),
      status: "pending",
      price_cents: 30_000
    }.merge(attrs))
  end

  describe "création d'un Stay pour un SpaceBooking qui n'en a pas" do
    it "crée le Stay, le StayItem et upserte le Customer par email" do
      space_booking = build_space_booking

      stay = described_class.call(space_booking)

      expect(stay).to be_persisted
      expect(space_booking.reload.stay).to eq(stay)
      expect(stay.customer.email).to eq("zoe@example.com")
      expect(stay.customer.phone).to eq("+32470112233")
      expect(stay.stay_items.map(&:bookable)).to contain_exactly(space_booking)
    end

    it "recopie dates, statut et montant depuis le space_booking sans le muter" do
      space_booking = build_space_booking

      expect { described_class.call(space_booking) }
        .not_to change { space_booking.reload.attributes }

      stay = space_booking.reload.stay
      expect(stay.arrival_date).to eq(Date.new(2026, 8, 1))
      expect(stay.departure_date).to eq(Date.new(2026, 8, 4))
      expect(stay.status).to eq("pending")
      expect(stay.total_amount_cents).to eq(30_000)
    end

    it "attribue toujours source 'manual' (pas de canal OTA pour les espaces)" do
      stay = described_class.call(build_space_booking)
      expect(stay.source).to eq("manual")
    end

    it "rattache un space_booking sans email exploitable au Customer fourre-tout" do
      stay = described_class.call(build_space_booking(email: nil))
      expect(stay.customer.catch_all?).to be(true)
    end

    it "crée un Customer organisation quand group_name est présent" do
      stay = described_class.call(
        build_space_booking(email: "asso@example.com", group_name: "Les Amis")
      )
      expect(stay.customer.customer_type).to eq("organization")
      expect(stay.customer.organization_name).to eq("Les Amis")
    end
  end

  describe "idempotence" do
    it "renvoie le Stay existant sans en créer un second" do
      space_booking = build_space_booking
      first = described_class.call(space_booking)

      second = nil
      expect { second = described_class.call(space_booking) }.not_to change(Stay, :count)
      expect(second).to eq(first)
      expect(StayItem.where(bookable: space_booking).count).to eq(1)
    end
  end

  describe "SpaceBooking soft-deleted" do
    it "ne crée aucun Stay et renvoie nil" do
      space_booking = build_space_booking
      space_booking.soft_delete!(validate: false)

      result = nil
      expect { result = described_class.call(space_booking) }.not_to change(Stay, :count)
      expect(result).to be_nil
      expect(StayItem.where(bookable: space_booking).count).to eq(0)
    end
  end

  # État latent (improbable mais possible) : un StayItem VIVANT pointant vers un
  # Stay soft-deleted. `space_booking.stay` (double scope vivant) vaut alors nil,
  # donc le service est rappelé. Sans le repoint, il créerait un 2e StayItem vivant
  # (unicité scoped sur stay_id ⇒ autorisé) et divergerait du compteur du backfill.
  describe "état latent : StayItem vivant → Stay soft-deleted" do
    def build_latent_state
      space_booking = build_space_booking(email: "latent@example.com")
      dead_stay = described_class.call(space_booking)
      dead_stay.soft_delete!(validate: false)
      # Le soft-delete du Stay cascade sur son StayItem : on le ressuscite pour
      # reconstruire l'état exact « StayItem vivant → Stay mort ».
      StayItem.with_deleted do
        StayItem.unscoped
          .find_by(bookable_id: space_booking.id, bookable_type: "SpaceBooking")
          .update_column(:deleted_at, nil)
      end
      [space_booking.reload, dead_stay]
    end

    it "repointe le StayItem orphelin au lieu d'en créer un second" do
      space_booking, dead_stay = build_latent_state
      expect(space_booking.stay).to be_nil
      expect(StayItem.where(bookable: space_booking).count).to eq(1)

      new_stay = described_class.call(space_booking)

      expect(StayItem.where(bookable: space_booking).count).to eq(1)
      expect(new_stay.id).not_to eq(dead_stay.id)
      expect(space_booking.reload.stay).to eq(new_stay)
    end
  end
end
