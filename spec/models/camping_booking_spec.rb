require "rails_helper"

# Epic #66, Phase 3 — CampingBooking : capacité GLOBALE du terrain, vérifiée nuit
# par nuit contre TOTAL_CAPACITY (seules les résas `confirmed` comptent).
RSpec.describe CampingBooking do
  let(:d0) { Date.today + 40 }
  let(:d1) { d0 + 1 }
  let(:d2) { d0 + 2 }

  def confirmed!(people:, from:, to:)
    described_class.create!(firstname: "X", from_date: from, to_date: to, people: people, status: "confirmed", kind: "tente")
  end

  it "génère un token et exige un nombre de personnes positif" do
    cb = described_class.create!(firstname: "A", from_date: d0, to_date: d1, people: 2, status: "pending")
    expect(cb.token).to be_present
    expect(described_class.new(firstname: "B", people: 0)).not_to be_valid
  end

  describe ".units_reserved_on" do
    it "somme les personnes confirmées couvrant la nuit (from <= d < to)" do
      confirmed!(people: 4, from: d0, to: d2) # couvre d0 et d1, pas d2
      expect(described_class.units_reserved_on(d0)).to eq(4)
      expect(described_class.units_reserved_on(d1)).to eq(4)
      expect(described_class.units_reserved_on(d2)).to eq(0)
    end

    it "ignore les résas non confirmées" do
      described_class.create!(firstname: "P", from_date: d0, to_date: d2, people: 4, status: "pending")
      expect(described_class.units_reserved_on(d0)).to eq(0)
    end
  end

  describe ".capacity_conflict_date" do
    it "renvoie la première nuit dépassant la capacité, nil sinon" do
      confirmed!(people: described_class::TOTAL_CAPACITY - 1, from: d0, to: d1)
      # +2 personnes la nuit d0 → dépasse ; la nuit d1 est libre.
      expect(described_class.capacity_conflict_date(units: 2, from: d0, to: d2)).to eq(d0)
      expect(described_class.capacity_conflict_date(units: 1, from: d0, to: d2)).to be_nil
    end

    it "exclut une réservation donnée (édition)" do
      own = confirmed!(people: described_class::TOTAL_CAPACITY, from: d0, to: d1)
      expect(described_class.capacity_conflict_date(units: 1, from: d0, to: d1)).to eq(d0)
      expect(described_class.capacity_conflict_date(units: 1, from: d0, to: d1, excluding_id: own.id)).to be_nil
    end
  end
end
