require "rails_helper"

# Issue #158 — enregistrement d'une fiche encodée en matrice.
RSpec.describe Finance::EncodePaperSheet do
  let(:sheet) { PaperSheet.create!(period_month: Date.new(2026, 8, 1), channel: "bar", entry_mode: "quantity") }

  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:ada) { MemberAccount.create!(kind: "household", household: household, name: "Ada") }
  let(:bob) { MemberAccount.create!(kind: "entity", name: "Semisto") }

  let(:moinette) do
    item = CatalogItem.create!(name: "Moinette", channel: "bar", unit: "piece")
    item.catalog_prices.create!(active_from: Date.new(2023, 1, 1), member_price_cents: 210)
    item
  end

  let(:chimay) do
    item = CatalogItem.create!(name: "Chimay", channel: "bar", unit: "piece")
    item.catalog_prices.create!(active_from: Date.new(2023, 1, 1), member_price_cents: 231)
    item
  end

  def encode(cells, mode: "quantity")
    described_class.new(sheet: sheet, cells: cells, entry_mode: mode).run!
  end

  describe "création" do
    it "crée UNE écriture par cellule non vide, toutes rattachées à la fiche" do
      report = encode({ ada.id => { moinette.id => "3", chimay.id => "1" }, bob.id => { moinette.id => "2" } })

      expect(report.created).to eq(3)
      expect(AccountEntry.where(paper_sheet_id: sheet.id).count).to eq(3)
    end

    it "multiplie la quantité par le prix sourcier du moment" do
      encode({ ada.id => { moinette.id => "3" } })

      entry = AccountEntry.last
      expect(entry.amount_cents).to eq(630)
      expect(entry.quantity).to eq(3)
      expect(entry.unit_price_cents).to eq(210)
    end

    it "ignore les cellules vides" do
      report = encode({ ada.id => { moinette.id => "", chimay.id => "   " } })

      expect(report.created).to eq(0)
      expect(AccountEntry.count).to eq(0)
    end

    it "ignore une cellule à zéro plutôt que d'écrire une écriture nulle" do
      report = encode({ ada.id => { moinette.id => "0" } })

      expect(report.created).to eq(0)
      expect(AccountEntry.count).to eq(0)
    end

    it "accepte la virgule décimale" do
      encode({ ada.id => { moinette.id => "1,5" } })

      expect(AccountEntry.last.amount_cents).to eq(315)
    end

    it "date les écritures du dernier jour du mois de la fiche" do
      encode({ ada.id => { moinette.id => "1" } })

      expect(AccountEntry.last.entry_date).to eq(Date.new(2026, 8, 31))
    end
  end

  # Le mode MONTANT reprend le tableur actuel, le mode QUANTITÉ la nouvelle vie.
  # Les deux doivent produire la même écriture pour un même total.
  describe "modes de saisie" do
    it "produit des écritures identiques pour un même total" do
      encode({ ada.id => { moinette.id => "3" } }, mode: "quantity")
      par_quantite = AccountEntry.last.amount_cents

      AccountEntry.delete_all
      encode({ ada.id => { moinette.id => "6,30" } }, mode: "amount")
      par_montant = AccountEntry.last.amount_cents

      expect(par_montant).to eq(par_quantite)
    end

    it "ne renseigne pas de quantité en mode montant" do
      encode({ ada.id => { moinette.id => "6,30" } }, mode: "amount")

      expect(AccountEntry.last.quantity).to be_nil
    end
  end

  # LA propriété qui rend l'écran rejouable : on corrige en revenant dessus.
  describe "réenregistrement" do
    before { encode({ ada.id => { moinette.id => "3", chimay.id => "1" } }) }

    it "ne duplique rien" do
      expect {
        encode({ ada.id => { moinette.id => "3", chimay.id => "1" } })
      }.not_to change(AccountEntry, :count)
    end

    it "met à jour une cellule modifiée au lieu d'en créer une seconde" do
      report = encode({ ada.id => { moinette.id => "5", chimay.id => "1" } })

      expect(report.updated).to eq(2)
      expect(AccountEntry.where(catalog_item_id: moinette.id).count).to eq(1)
      expect(AccountEntry.find_by(catalog_item_id: moinette.id).amount_cents).to eq(1050)
    end

    it "supprime l'écriture d'une cellule vidée" do
      report = encode({ ada.id => { moinette.id => "", chimay.id => "1" } })

      expect(report.deleted).to eq(1)
      expect(AccountEntry.where(catalog_item_id: moinette.id)).to be_empty
    end
  end

  describe "écriture verrouillée" do
    before do
      encode({ ada.id => { moinette.id => "3" } })
      AccountEntry.last.update_column(:locked_at, Time.current)
    end

    it "ne la modifie pas et la signale" do
      report = encode({ ada.id => { moinette.id => "9" } })

      expect(report.locked).to eq(1)
      expect(report.updated).to eq(0)
      expect(AccountEntry.last.amount_cents).to eq(630)
    end

    it "ne la supprime pas non plus quand la cellule est vidée" do
      report = encode({ ada.id => { moinette.id => "" } })

      expect(report.locked).to eq(1)
      expect(AccountEntry.count).to eq(1)
    end
  end

  it "marque la fiche comme encodée" do
    encode({ ada.id => { moinette.id => "1" } })

    expect(sheet.reload.status).to eq("encoded")
    expect(sheet.encoded_at).to be_present
  end

  it "n'écrit rien pour un article sans prix à la date de la fiche" do
    sans_prix = CatalogItem.create!(name: "Sans prix", channel: "bar")

    report = encode({ ada.id => { sans_prix.id => "3" } })

    expect(report.created).to eq(0)
  end
end
