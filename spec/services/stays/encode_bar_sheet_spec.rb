require "rails_helper"

# Feuille de bar d'un groupe (Michael, 2026-10-13) : les consommations notées
# sur la feuille s'ajoutent au séjour, au prix public du catalogue.
RSpec.describe Stays::EncodeBarSheet do
  let(:customer) do
    Customer.create!(email: "scouts@example.com", customer_type: "organization", organization_name: "Scouts de Namur")
  end
  let(:stay) do
    Stay.create!(customer: customer, status: "confirmed",
                 arrival_date: Date.new(2026, 10, 8), departure_date: Date.new(2026, 10, 11))
  end
  let!(:biere) do
    CatalogItem.create!(name: "Moinette", channel: "bar").tap do |item|
      item.catalog_prices.create!(active_from: Date.new(2026, 1, 1), member_price_cents: 250, public_price_cents: 350)
    end
  end
  let!(:soft) do
    CatalogItem.create!(name: "Limonade", channel: "bar").tap do |item|
      item.catalog_prices.create!(active_from: Date.new(2026, 1, 1), member_price_cents: 150)
    end
  end

  before do
    LinenOrder.create!(stay: stay, kind: "double_bed", quantity: 1, price_cents: 10_000)
    stay.recompute_aggregates!
  end

  def encode(quantities, mode = "set")
    service = described_class.new(stay: stay, quantities: quantities, mode: mode)
    expect(service.run).to be_truthy
    service.report
  end

  it "ajoute les lignes au prix public et les compte dans le total du séjour" do
    report = encode({ biere.id.to_s => "6", soft.id.to_s => "2" })

    expect(report.created).to eq(2)
    ligne = stay.bar_consumptions.find_by(catalog_item: biere)
    expect([ligne.quantity, ligne.unit_price_cents, ligne.price_cents]).to eq([6, 350, 2_100])
    # Sans prix public, le prix sourcier plutôt qu'une ligne infacturable.
    expect(stay.bar_consumptions.find_by(catalog_item: soft).unit_price_cents).to eq(150)
    expect(stay.reload.total_amount_cents).to eq(10_000 + 2_100 + 300)
  end

  it "met à jour sans dupliquer, et retire une ligne vidée" do
    encode({ biere.id => 6, soft.id => 2 })
    report = encode({ biere.id => 4, soft.id => "" })

    expect([report.updated, report.deleted]).to eq([1, 1])
    expect(stay.bar_consumptions.count).to eq(1)
    expect(stay.reload.total_amount_cents).to eq(10_000 + 1_400)
  end

  it "additionne une seconde feuille en mode « add »" do
    encode({ biere.id => 6 })
    encode({ biere.id => 3 }, "add")

    expect(stay.bar_consumptions.sole.quantity).to eq(9)
  end

  it "garde le prix figé à la création quand le tarif change ensuite" do
    encode({ biere.id => 2 })
    biere.catalog_prices.first.update!(public_price_cents: 400)
    encode({ biere.id => 3 })

    expect(stay.bar_consumptions.sole.price_cents).to eq(1_050)
  end

  it "signale un article sans prix à la date du séjour et ignore ce qui n'est pas du bar" do
    sans_prix = CatalogItem.create!(name: "Kombucha", channel: "bar")
    cellier = CatalogItem.create!(name: "Farine", channel: "grocery")

    report = encode({ sans_prix.id => 2, cellier.id => 1 })

    expect(report.unpriced).to eq(["Kombucha"])
    expect(report.ignored).to eq(1)
    expect(stay.bar_consumptions).to be_empty
  end

  it "s'ajoute au prix imposé au lieu d'être absorbé par lui" do
    stay.update!(price_override_cents: 50_000)
    encode({ biere.id => 2 })

    expect(stay.reload.total_amount_cents).to eq(50_000 + 700)
  end
end
