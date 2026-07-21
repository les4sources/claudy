require "rails_helper"

# Issue #124 — table des tarifs paramétrables.
RSpec.describe Rate, type: :model do
  it "exige une clé unique" do
    Rate.create!(key: "van.per_night", amount_cents: 1_500, label: "Van")
    duplicate = Rate.new(key: "van.per_night", amount_cents: 2_000)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:key]).to be_present
  end

  it "refuse un montant négatif" do
    rate = Rate.new(key: "van.per_night", amount_cents: -1)

    expect(rate).not_to be_valid
    expect(rate.errors[:amount_cents]).to be_present
  end

  it "refuse une unité inconnue" do
    expect(Rate.new(key: "x", amount_cents: 0, unit: "bananes")).not_to be_valid
  end

  it "expose le montant en euros, ou en points de pourcentage" do
    expect(Rate.new(key: "a", amount_cents: 1_550).amount).to eq(15.5)
    expect(Rate.new(key: "b", amount_cents: 50, unit: "percent").amount).to eq(50)
  end

  it "trace les modifications avec PaperTrail" do
    rate = Rate.create!(key: "van.per_night", amount_cents: 1_500)
    expect { rate.update!(amount_cents: 1_800) }.to change { rate.versions.count }.by(1)
  end

  describe ".grouped" do
    it "range chaque tarif dans son domaine, groupes dans l'ordre" do
      Rate.create!(key: "meal.buffet.per_person", amount_cents: 1_200)
      Rate.create!(key: "lodging.la_hulotte.first_night", amount_cents: 48_500)
      Rate.create!(key: "dog.supplement", amount_cents: 5_000)

      expect(Rate.grouped.map(&:first)).to eq(["Hébergements", "Repas", "Divers"])
    end
  end
end
