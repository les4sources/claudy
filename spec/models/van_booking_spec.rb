require "rails_helper"

# VanBooking : capacité GLOBALE en véhicules, configurable sans redéploiement (issue #78).
RSpec.describe VanBooking do
  let(:d0) { Date.today + 40 }
  let(:d1) { d0 + 1 }

  def confirmed!(vehicles:, from:, to:)
    described_class.create!(firstname: "X", from_date: from, to_date: to, vehicles: vehicles, status: "confirmed")
  end

  describe ".total_capacity (configurable — issue #78)" do
    it "vaut la constante par défaut sans config" do
      expect(described_class.total_capacity).to eq(described_class::TOTAL_CAPACITY)
    end

    it "est surchargée par le Setting et ajuste le veto de capacité" do
      Setting.set(described_class::CAPACITY_SETTING_KEY, described_class::TOTAL_CAPACITY + 3)
      expect(described_class.total_capacity).to eq(described_class::TOTAL_CAPACITY + 3)

      confirmed!(vehicles: described_class::TOTAL_CAPACITY, from: d0, to: d1)
      expect(described_class.capacity_conflict_date(units: 3, from: d0, to: d1)).to be_nil
      expect(described_class.remaining_on(d0)).to eq(3)
    end

    it "n'affecte pas la capacité camping (clé distincte)" do
      Setting.set(described_class::CAPACITY_SETTING_KEY, 99)
      expect(CampingBooking.total_capacity).to eq(CampingBooking::TOTAL_CAPACITY)
    end
  end
end
