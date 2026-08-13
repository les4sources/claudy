require "rails_helper"

# Issue #156 — barèmes datés. Une clé peut porter plusieurs valeurs successives ;
# la seule règle dure est qu'elles ne se recouvrent jamais.
RSpec.describe RateVersion, type: :model do
  let(:rate) { Rate.create!(key: "pot.monthly_per_adult", amount_cents: 1_000, label: "Cagnotte") }

  def version(from:, until_date: nil, amount: 1_000)
    rate.rate_versions.new(amount_cents: amount, active_from: from, active_until: until_date)
  end

  it "refuse une fin antérieure au début" do
    invalid = version(from: Date.new(2024, 6, 1), until_date: Date.new(2024, 5, 31))

    expect(invalid).not_to be_valid
    expect(invalid.errors[:active_until]).to be_present
  end

  it "accepte une période d'un seul jour" do
    expect(version(from: Date.new(2024, 6, 1), until_date: Date.new(2024, 6, 1))).to be_valid
  end

  describe "chevauchement" do
    before { version(from: Date.new(2023, 1, 1), until_date: Date.new(2024, 12, 31)).save! }

    it "refuse une version qui démarre à l'intérieur d'une période existante" do
      overlapping = version(from: Date.new(2024, 6, 1))

      expect(overlapping).not_to be_valid
      expect(overlapping.errors[:active_from]).to be_present
    end

    it "refuse une version antérieure qui recouvre la période existante" do
      overlapping = version(from: Date.new(2022, 1, 1), until_date: Date.new(2023, 6, 30))

      expect(overlapping).not_to be_valid
      expect(overlapping.errors[:active_until]).to be_present
    end

    it "refuse une version ouverte qui démarre avant une période existante" do
      overlapping = version(from: Date.new(2022, 1, 1))

      expect(overlapping).not_to be_valid
    end

    it "accepte une version qui reprend le lendemain de la précédente" do
      expect(version(from: Date.new(2025, 1, 1))).to be_valid
    end

    it "ne se considère pas comme son propre chevauchement à la mise à jour" do
      existing = rate.rate_versions.first

      expect { existing.update!(amount_cents: 1_200) }.not_to raise_error
    end

    it "refuse une deuxième version démarrant le même jour (index unique)" do
      duplicate = version(from: Date.new(2023, 1, 1), amount: 2_000)

      expect(duplicate).not_to be_valid
    end
  end

  describe "#covers?" do
    let(:closed) { version(from: Date.new(2023, 1, 1), until_date: Date.new(2027, 4, 30)) }

    it "couvre ses deux bornes incluses" do
      expect(closed.covers?(Date.new(2023, 1, 1))).to be(true)
      expect(closed.covers?(Date.new(2027, 4, 30))).to be(true)
    end

    it "ne couvre ni la veille du début ni le lendemain de la fin" do
      expect(closed.covers?(Date.new(2022, 12, 31))).to be(false)
      expect(closed.covers?(Date.new(2027, 5, 1))).to be(false)
    end

    it "couvre indéfiniment quand la fin est nulle" do
      expect(version(from: Date.new(2023, 1, 1)).covers?(Date.new(2099, 1, 1))).to be(true)
    end
  end
end
