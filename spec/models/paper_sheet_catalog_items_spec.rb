require "rails_helper"

# Issue #193 — une fiche ancienne doit montrer SES articles.
#
# Le piège, avant : `CatalogItem.active` filtrait la colonne de gauche de
# l'écran d'encodage. Reprendre février 2022 imposait donc de garder actifs une
# soixantaine d'articles qui ne sont plus vendus depuis quatre ans — et de les
# afficher sur la fiche du mois courant.
RSpec.describe PaperSheet, "#catalog_items" do
  let(:sheet) { described_class.create!(period_month: Date.new(2022, 2, 1), channel: "bar") }
  let!(:vendu) { CatalogItem.create!(name: "Moinette", channel: "bar") }
  let!(:disparu) { CatalogItem.create!(name: "Grosse Bertha", channel: "bar", active: false) }
  let!(:cellier) { CatalogItem.create!(name: "Avoine bio", channel: "grocery") }
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  it "ne montre que les articles actifs du canal quand la fiche est vierge" do
    expect(sheet.catalog_items).to contain_exactly(vendu)
  end

  it "ajoute les articles disparus que la fiche porte déjà" do
    AccountEntry.create!(member_account: account, entry_date: sheet.entry_date, amount_cents: 197,
                         label: "Grosse Bertha", catalog_item_id: disparu.id, paper_sheet_id: sheet.id)

    expect(sheet.catalog_items).to contain_exactly(vendu, disparu)
  end

  it "n'importe pas les articles disparus d'une AUTRE fiche" do
    autre = described_class.create!(period_month: Date.new(2022, 3, 1), channel: "bar")
    AccountEntry.create!(member_account: account, entry_date: autre.entry_date, amount_cents: 197,
                         label: "Grosse Bertha", catalog_item_id: disparu.id, paper_sheet_id: autre.id)

    expect(sheet.catalog_items).to contain_exactly(vendu)
  end

  it "reste borné à son canal" do
    expect(sheet.catalog_items).not_to include(cellier)
  end

  it "ne double pas un article à la fois actif et déjà porté par la fiche" do
    AccountEntry.create!(member_account: account, entry_date: sheet.entry_date, amount_cents: 210,
                         label: "Moinette", catalog_item_id: vendu.id, paper_sheet_id: sheet.id)

    expect(sheet.catalog_items.to_a.count(vendu)).to eq(1)
  end
end

# Le pendant côté écriture : l'écran décide de ce qu'il PROPOSE, le service
# honore un identifiant explicitement fourni. Sans ça, chaque cellule d'une
# fiche de 2022 tomberait silencieusement dans `ignored`.
RSpec.describe Finance::EncodePaperSheet, "sur une fiche historique" do
  let(:sheet) { PaperSheet.create!(period_month: Date.new(2022, 2, 1), channel: "bar", entry_mode: "amount") }
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }
  let!(:disparu) { CatalogItem.create!(name: "Grosse Bertha", channel: "bar", active: false) }

  it "encode une cellule sur un article qui n'est plus vendu" do
    report = described_class.new(sheet: sheet, cells: { account.id.to_s => { disparu.id.to_s => "21.66" } },
                                 entry_mode: "amount").run!

    expect(report.created).to eq(1)
    expect(report.ignored).to eq(0)
    expect(account.account_entries.sole.amount_cents).to eq(2166)
  end

  # Un import de masse doit dire ce qu'il n'a pas su lire, pas tomber au milieu
  # d'un mois sur une ligne malformée.
  it "compte une ligne malformée comme ignorée au lieu de tomber" do
    report = described_class.new(sheet: sheet, cells: { account.id.to_s => "21.66" },
                                 entry_mode: "amount").run!

    expect(report.ignored).to eq(1)
    expect(report.created).to eq(0)
  end

  it "ignore toujours un article d'un autre canal" do
    ailleurs = CatalogItem.create!(name: "Avoine bio", channel: "grocery")

    report = described_class.new(sheet: sheet, cells: { account.id.to_s => { ailleurs.id.to_s => "3.00" } },
                                 entry_mode: "amount").run!

    expect(report.ignored).to eq(1)
    expect(account.account_entries).to be_empty
  end
end
