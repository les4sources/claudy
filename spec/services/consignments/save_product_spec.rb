require "rails_helper"

# Epic #359, phase 2 — un produit géré par l'artisan : un article `craft` à son
# nom, un prix dans un palier daté qui ne réécrit jamais le passé.
RSpec.describe Consignments::SaveProduct do
  let(:consignor) { Consignor.create!(name: "Eline", settlement_mode: "invoice") }
  let(:today) { Date.new(2026, 9, 23) }

  def save(product: nil, on: today, **attrs)
    service = described_class.new(consignor: consignor, product: product, on: on)
    [service, service.run(**{ name: "Savon", unit: "piece", price_euros: "4,50" }.merge(attrs))]
  end

  it "crée l'article d'artisanat et son premier palier, prix public = prix habitant" do
    service, ok = save
    expect(ok).to be(true)

    item = service.product
    expect(item).to be_persisted
    expect(item.channel).to eq("craft")
    expect(item.consignor).to eq(consignor)
    tier = item.catalog_prices.sole
    expect(tier.active_from).to eq(today)
    expect(tier.active_until).to be_nil
    expect([tier.public_price_cents, tier.member_price_cents]).to eq([450, 450])
  end

  it "refuse un prix illisible sans rien créer" do
    service, ok = save(price_euros: "quatre")
    expect(ok).to be(false)
    expect(service.error_message).to eq("Indiquez un prix de vente.")
    expect(CatalogItem.count).to eq(0)
  end

  it "refuse un nom vide sans rien créer" do
    _, ok = save(name: " ")
    expect(ok).to be(false)
    expect(CatalogItem.count).to eq(0)
  end

  it "ouvre un nouveau palier et clôture l'ancien la veille" do
    item = save(on: today - 10).first.product

    _, ok = save(product: item, price_euros: "5")
    expect(ok).to be(true)

    tiers = item.catalog_prices.chronological.to_a
    expect(tiers.size).to eq(2)
    expect(tiers.first.active_until).to eq(today - 1)
    expect(tiers.last.active_from).to eq(today)
    expect(item.price_on(today - 1).public_price_cents).to eq(450)
    expect(item.price_on(today).public_price_cents).to eq(500)
  end

  it "ne crée pas de palier quand le prix ne change pas" do
    item = save(on: today - 10).first.product
    save(product: item, name: "Savon au miel")

    expect(item.reload.name).to eq("Savon au miel")
    expect(item.catalog_prices.count).to eq(1)
  end
end
