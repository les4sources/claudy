require "rails_helper"

# HamacBooking (issue #138) — location de hamacs persistée sur le séjour.
# La capacité n'est PAS une constante du domaine mais le STOCK du `RentalItem`
# correspondant ; stock non renseigné = aucune limite.
RSpec.describe HamacBooking do
  let(:arrival) { Date.today + 30 }

  def hamac(kind: "simple", count: 1, from: arrival, to: arrival + 2, status: "confirmed")
    described_class.create!(kind: kind, count: count, from_date: from, to_date: to, status: status)
  end

  describe "validations" do
    it "refuse un kind inconnu" do
      record = described_class.new(kind: "triple", count: 1)
      expect(record).not_to be_valid
      expect(record.errors[:kind]).to be_present
    end

    it "refuse un count nul ou négatif" do
      expect(described_class.new(kind: "simple", count: 0)).not_to be_valid
      expect(described_class.new(kind: "simple", count: -1)).not_to be_valid
    end

    it "génère un token à la création" do
      expect(hamac.token).to be_present
    end
  end

  describe ".total_stock" do
    it "lit le stock du RentalItem correspondant" do
      RentalItem.create!(name: "Hamac simple", stock: 4, price_cents: 750)
      expect(described_class.total_stock("simple")).to eq(4)
    end

    it "vaut nil quand l'article n'existe pas (capacité non bornée)" do
      expect(described_class.total_stock("double")).to be_nil
    end
  end

  describe ".units_reserved_on" do
    before { RentalItem.create!(name: "Hamac simple", stock: 4, price_cents: 750) }

    it "ne compte que les réservations CONFIRMÉES couvrant la nuit" do
      hamac(count: 2, status: "confirmed")
      hamac(count: 3, status: "pending")

      expect(described_class.units_reserved_on("simple", arrival)).to eq(2)
      # Nuit hors fenêtre [from, to) : rien.
      expect(described_class.units_reserved_on("simple", arrival + 2)).to eq(0)
    end

    it "n'agrège jamais les autres types de hamac" do
      hamac(kind: "double", count: 2)
      expect(described_class.units_reserved_on("simple", arrival)).to eq(0)
    end

    it "sait exclure des réservations données (édition)" do
      own = hamac(count: 2)
      expect(described_class.units_reserved_on("simple", arrival, excluding_id: [own.id])).to eq(0)
    end
  end

  describe ".capacity_conflict_date" do
    it "renvoie la première nuit en rupture de stock" do
      RentalItem.create!(name: "Hamac simple", stock: 3, price_cents: 750)
      hamac(count: 2, from: arrival + 1, to: arrival + 2)

      conflict = described_class.capacity_conflict_date(
        kind: "simple", units: 2, from: arrival, to: arrival + 3
      )
      expect(conflict).to eq(arrival + 1)
    end

    it "ne bloque jamais quand le stock n'est pas renseigné" do
      RentalItem.create!(name: "Hamac simple", stock: nil, price_cents: 750)
      hamac(count: 50)

      expect(described_class.capacity_conflict_date(
        kind: "simple", units: 50, from: arrival, to: arrival + 2
      )).to be_nil
    end

    it "ne signale rien quand le stock suffit" do
      RentalItem.create!(name: "Hamac simple", stock: 4, price_cents: 750)
      hamac(count: 2)

      expect(described_class.capacity_conflict_date(
        kind: "simple", units: 2, from: arrival, to: arrival + 2
      )).to be_nil
    end
  end
end
