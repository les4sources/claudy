require "rails_helper"

# Canal DPH (droguerie, parfumerie, hygiène — Michael, 2026-09-30) : un canal du
# CATALOGUE dont les articles se vendent au cellier et se notent sur sa fiche.
RSpec.describe "Canal DPH" do
  let!(:savon) { CatalogItem.create!(name: "Savon main et corps", channel: "dph", unit: "l") }
  let!(:avoine) { CatalogItem.create!(name: "Avoine", channel: "grocery", unit: "kg") }
  let!(:moinette) { CatalogItem.create!(name: "Moinette", channel: "bar", unit: "piece") }

  it "est un canal valide, libellé « DPH »" do
    expect(savon).to be_valid
    expect(savon.channel_label).to eq("DPH")
  end

  it "apparaît sur la fiche papier du cellier, pas sur celle du bar" do
    cellier = PaperSheet.create!(period_month: Date.new(2026, 10, 1), channel: "grocery")
    bar = PaperSheet.create!(period_month: Date.new(2026, 10, 1), channel: "bar")

    expect(cellier.catalog_items).to contain_exactly(avoine, savon)
    expect(bar.catalog_items).to contain_exactly(moinette)
  end

  it "s'encode sur la fiche du cellier, en flux épicerie" do
    savon.catalog_prices.create!(active_from: Date.new(2026, 1, 1), member_price_cents: 1680)
    sheet = PaperSheet.create!(period_month: Date.new(2026, 10, 1), channel: "grocery", entry_mode: "quantity")
    household = Household.create!(name: "Chevêche", kind: "resident")
    account = MemberAccount.create!(kind: "household", household: household, name: "Chevêche")

    report = Finance::EncodePaperSheet.new(sheet: sheet, cells: { account.id => { savon.id => "2" } }, entry_mode: "quantity").run!

    expect(report.created).to eq(1)
    entry = AccountEntry.last
    expect(entry.catalog_item_id).to eq(savon.id)
    expect(entry.amount_cents).to eq(3360)
    expect(entry.flow).to eq("grocery")
  end

  it "emprunte la marge sourcier du cellier, réglable dans Tarifs" do
    Rate.create!(key: "catalog.margin.grocery", amount_cents: 17, unit: "percent")
        .rate_versions.create!(amount_cents: 17, active_from: Date.new(2023, 1, 1))

    expect(Catalog::BuildPrice.margin_key("dph")).to eq("catalog.margin.grocery")
    expect(Catalog::BuildPrice.new(channel: "dph", purchase_price_cents: 1436).member_price_cents).to eq(1680)
  end

  it "retombe sur la marge par défaut du cellier sans paramètre" do
    expect(Catalog::BuildPrice.new(channel: "dph").margin_percent).to eq(17)
  end
end
