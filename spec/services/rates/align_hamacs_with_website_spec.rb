require "rails_helper"

# Epic #260, phase 2, décision 7 — le site vend le hamac 10 €, simple comme
# double. La tâche corrige les deux endroits qui portent un prix (la table
# `rates` et les `RentalItem`), sans jamais écraser une valeur posée à la main.
RSpec.describe Rates::AlignHamacsWithWebsite do
  it "ne touche à rien en dry-run" do
    Rate.create!(key: "hamac.simple", amount_cents: 750, label: "Hamac simple")
    RentalItem.create!(name: "Hamac double", stock: 3, price_cents: 1_500)

    described_class.new(dry_run: true).run

    expect(Rate.find_by(key: "hamac.simple").amount_cents).to eq(750)
    expect(RentalItem.find_by(name: "Hamac double").price_cents).to eq(1_500)
  end

  it "crée les clés manquantes à 10 €" do
    described_class.new(dry_run: false).run

    expect(Rate.find_by(key: "hamac.simple").amount_cents).to eq(1_000)
    expect(Rate.find_by(key: "hamac.double").amount_cents).to eq(1_000)
  end

  it "réaligne les anciennes valeurs de repli (750 / 1 500) sur 10 €" do
    Rate.create!(key: "hamac.simple", amount_cents: 750, label: "Hamac simple")
    Rate.create!(key: "hamac.double", amount_cents: 1_500, label: "Hamac double")

    result = described_class.new(dry_run: false).run

    expect(Rate.find_by(key: "hamac.simple").amount_cents).to eq(1_000)
    expect(Rate.find_by(key: "hamac.double").amount_cents).to eq(1_000)
    expect(result.aligned.size).to eq(2)
  end

  it "réaligne aussi le prix des RentalItem physiques" do
    simple = RentalItem.create!(name: "Hamac simple", stock: 4, price_cents: 750)
    double = RentalItem.create!(name: "Hamac double", stock: 2, price_cents: 1_500)

    described_class.new(dry_run: false).run

    expect(simple.reload.price_cents).to eq(1_000)
    expect(double.reload.price_cents).to eq(1_000)
  end

  it "ne crée jamais un RentalItem absent — son stock n'est pas notre affaire" do
    expect { described_class.new(dry_run: false).run }.not_to change(RentalItem, :count)
  end

  it "conserve une valeur éditée à la main et la signale" do
    Rate.create!(key: "hamac.simple", amount_cents: 1_250, label: "Hamac simple — négocié")
    RentalItem.create!(name: "Hamac double", stock: 2, price_cents: 1_800)

    result = described_class.new(dry_run: false).run

    expect(Rate.find_by(key: "hamac.simple").amount_cents).to eq(1_250)
    expect(RentalItem.find_by(name: "Hamac double").price_cents).to eq(1_800)
    expect(result.kept.join(" ")).to include("hamac.simple").and include("Hamac double")
  end

  it "est idempotente : un second passage ne change plus rien" do
    described_class.new(dry_run: false).run
    result = described_class.new(dry_run: false).run

    expect(result.aligned).to be_empty
    expect(result.created).to be_empty
  end
end
