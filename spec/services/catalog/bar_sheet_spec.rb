require "rails_helper"

# Fiche du bar à imprimer (Catalogue, Michael 2026-11-01).
RSpec.describe Catalog::BarSheet do
  def item(name, category: nil, channel: "bar", active: true, member_cents: 200, from: Date.new(2026, 1, 1))
    CatalogItem.create!(name: name, channel: channel, category: category, unit: "piece", active: active).tap do |record|
      next if member_cents.nil?

      record.catalog_prices.create!(active_from: from, purchase_price_cents: 100,
                                    member_price_cents: member_cents, public_price_cents: member_cents * 2)
    end
  end

  let(:november) { Date.new(2026, 11, 1) }

  it "ne garde que les articles actifs du canal Bar" do
    item("Moinette", category: "Bières")
    item("Vieille bière", category: "Bières", active: false)
    item("Avoine", category: "Vracs", channel: "grocery")

    names = described_class.new(month: november).groups.flat_map(&:lines).map { |line| line.item.name }

    expect(names).to eq(["Moinette"])
  end

  it "range les catégories comme l'ancienne fiche, puis les autres, puis les sans catégorie" do
    item("Chips", category: "Snacks")
    item("Miel")
    item("Kombucha", category: "Softs")
    item("Glace", category: "Desserts")
    item("Vin verre", category: "Vin")
    item("Moinette", category: "Bières")

    groups = described_class.new(month: november).groups

    expect(groups.map(&:name)).to eq(%w[Bières Vin Softs Snacks Desserts Autres])
    expect(groups.first.emoji).to eq("🍺")
    expect(groups.first.tone).to eq("socioculturel")
  end

  it "prend le prix sourcier en vigueur à la fin du mois, celui de l'encodage" do
    moinette = item("Moinette", category: "Bières", member_cents: 210)
    moinette.catalog_prices.first.update!(active_until: Date.new(2026, 11, 14))
    moinette.catalog_prices.create!(active_from: Date.new(2026, 11, 15), purchase_price_cents: 110,
                                    member_price_cents: 230, public_price_cents: 420)

    line = described_class.new(month: november).groups.first.lines.first

    expect(line.price_cents).to eq(230)
  end

  it "signale les articles sans prix" do
    item("Nouveauté", category: "Bières", member_cents: nil)

    expect(described_class.new(month: november).missing_prices.map(&:name)).to eq(["Nouveauté"])
  end

  it "met une colonne par compte sourcier actif" do
    MemberAccount.create!(kind: "entity", name: "Seb & Mag")
    MemberAccount.create!(kind: "entity", name: "Béné")
    MemberAccount.create!(kind: "entity", name: "Émilie")
    MemberAccount.create!(kind: "entity", name: "Parti", active: false)

    # Sans tenir compte des accents : Émilie entre Béné et Seb & Mag.
    expect(described_class.new(month: november).accounts.map(&:name)).to eq(["Béné", "Émilie", "Seb & Mag"])
  end

  it "lit le mois AAAA-MM, le mois en cours sinon" do
    expect(described_class.parse_month("2026-12")).to eq(Date.new(2026, 12, 1))
    expect(described_class.parse_month("n'importe quoi")).to eq(Date.current.beginning_of_month)
  end
end
