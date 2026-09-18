require "rails_helper"

# Issue #339 — le miroir d'une Pizza Party privée payée sur Tranches de Vie.
RSpec.describe PartyReservation, type: :model do
  let(:customer) { Customer.create!(email: "party@example.com", customer_type: "organization", organization_name: "Scouts de Namur") }
  let(:stay) { Stay.create!(customer: customer, status: "confirmed") }

  def build_reservation(**attrs)
    described_class.create!({
      stay: stay, source: "tranchesdevie", external_id: 1234, external_number: "TV-20261009-0007",
      held_on: Date.new(2026, 10, 9), slot: "soir", group_name: "Scouts de Namur",
      persons: 18, forfait: true, price_cents: 27_000, status: "active"
    }.merge(attrs))
  end

  describe "les validations" do
    it "accepte une party conforme au contrat" do
      expect(build_reservation).to be_valid
    end

    it "refuse une source inconnue" do
      reservation = described_class.new(stay: stay, source: "ailleurs", external_id: 1, price_cents: 0)
      expect(reservation).not_to be_valid
      expect(reservation.errors[:source]).to be_present
    end

    it "refuse un statut hors des trois connus" do
      reservation = described_class.new(stay: stay, source: "tranchesdevie", external_id: 1, price_cents: 0, status: "peut-etre")
      expect(reservation).not_to be_valid
      expect(reservation.errors[:status]).to be_present
    end

    it "refuse de rattacher deux fois la même commande" do
      build_reservation
      autre_stay = Stay.create!(customer: customer, status: "confirmed")
      doublon = described_class.new(stay: autre_stay, source: "tranchesdevie", external_id: 1234, price_cents: 100)
      expect(doublon).not_to be_valid
      expect(doublon.errors[:external_id]).to be_present
    end

    it "laisse re-rattacher une commande précédemment détachée (soft-delete)" do
      reservation = build_reservation
      reservation.soft_delete!(validate: false)

      autre_stay = Stay.create!(customer: customer, status: "confirmed")
      expect(described_class.new(stay: autre_stay, source: "tranchesdevie", external_id: 1234, price_cents: 100)).to be_valid
    end
  end

  describe "l'affichage" do
    it "résume la party en une ligne" do
      expect(build_reservation.summary).to include("soir", "Scouts de Namur", "18 pers.")
    end

    it "nomme son statut en français" do
      expect(build_reservation(status: "refunded").status_label).to eq("Remboursée")
    end
  end

  describe "les scopes" do
    it "sépare l'active de ce qui est sorti" do
      active = build_reservation
      remboursee = build_reservation(external_id: 9999, status: "refunded")

      expect(described_class.active).to eq([active])
      expect(described_class.settled_elsewhere).to eq([remboursee])
    end
  end
end
