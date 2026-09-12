require "rails_helper"

# Epic #260, phase 1 — la tâche qui met la table `rates` en conformité avec le
# site : elle crée les cinq briques, retire les clés mortes, et ne touche jamais
# à un montant qu'un humain a posé.
RSpec.describe Rates::AlignLodgingsWithWebsite do
  def key(name, brick) = Pricing::Catalog.lodging_brick_key(name, brick)

  it "ne touche à rien en dry-run" do
    expect { described_class.new(dry_run: true).run }.not_to change(Rate, :count)
  end

  it "crée les cinq briques de chaque gîte du site" do
    described_class.new(dry_run: false).run

    expect(Rate.find_by(key: key("La Chevêche", "weeknight")).amount_cents).to eq(20_000)
    expect(Rate.find_by(key: key("La Hulotte", "package_4_nights")).amount_cents).to eq(149_000)
    expect(Rate.find_by(key: key("Le Grand-Duc", "package_6_nights")).amount_cents).to eq(290_000)
    expect(Rate.find_by(key: key("La Chevêche", "weeknight")).label).to include("nuit en semaine")
  end

  it "retire les anciennes clés des trois gîtes, devenues mortes" do
    Rate.create!(key: "lodging.la_hulotte.first_night", amount_cents: 48_500, label: "Hulotte — première nuit")

    described_class.new(dry_run: false).run

    expect(Rate.find_by(key: "lodging.la_hulotte.first_night")).to be_nil
  end

  it "laisse la Tiny house tranquille : elle se tarifie encore par la formule" do
    Rates::SeedFromCatalog.new.run

    described_class.new(dry_run: false).run

    expect(Rate.find_by(key: "lodging.tiny_house.first_night")).to be_present
    expect(Rate.find_by(key: "lodging.tiny_house.extra_night")).to be_present
  end

  it "ne retire pas en silence une ancienne clé éditée à la main" do
    Rate.create!(key: "lodging.la_hulotte.extra_night", amount_cents: 29_900, label: "Hulotte — négocié")

    result = described_class.new(dry_run: false).run

    expect(Rate.find_by(key: "lodging.la_hulotte.extra_night")).to be_present
    expect(result.kept.join).to include("lodging.la_hulotte.extra_night")
  end

  it "n'écrase pas une brique déjà éditée à la main" do
    Rate.create!(key: key("La Hulotte", "weeknight"), amount_cents: 42_000, label: "Hulotte — négocié")

    result = described_class.new(dry_run: false).run

    expect(Rate.find_by(key: key("La Hulotte", "weeknight")).amount_cents).to eq(42_000)
    expect(result.kept.join).to include("weeknight")
  end

  it "est idempotent" do
    described_class.new(dry_run: false).run

    expect { described_class.new(dry_run: false).run }.not_to change(Rate, :count)
  end
end
