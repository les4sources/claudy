require "rails_helper"

# Les douze mois d'un compte, tels qu'un habitant les lit.
#
# Le piège de ce genre d'agrégat, c'est le mois vide : il doit occuper une
# colonne (sinon la série ment sur le rythme) mais ne doit pas entrer dans la
# moyenne (sinon un compte ouvert en mai affiche une moyenne divisée par deux).
RSpec.describe MemberAccounts::Retrospective do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }
  let(:today) { Date.new(2026, 8, 19) }

  def conso(date, cents, flow: "bar", label: "Conso", item: nil, quantity: nil)
    account.account_entries.create!(entry_date: date, amount_cents: cents, flow: flow, label: label,
                                    catalog_item_id: item&.id, quantity: quantity)
  end

  subject(:bilan) { described_class.new(account, today: today) }

  describe "la fenêtre" do
    it "couvre douze mois glissants, mois courant inclus" do
      expect(bilan.debut).to eq(Date.new(2025, 9, 1))
      expect(bilan.fin).to eq(Date.new(2026, 8, 31))
      expect(bilan.mois.size).to eq(12)
    end

    it "garde les mois vides comme colonnes" do
      conso(Date.new(2026, 8, 3), 1_000)

      expect(bilan.mois.count { |m| m.total_cents.zero? }).to eq(11)
      expect(bilan.mois.last.total_cents).to eq(1_000)
    end

    it "ignore ce qui précède la fenêtre" do
      conso(Date.new(2025, 8, 31), 50_000)
      conso(Date.new(2026, 1, 15), 2_000)

      expect(bilan.total_depense_cents).to eq(2_000)
    end
  end

  describe "la répartition par canal" do
    before do
      conso(Date.new(2026, 6, 3), 6_000, flow: "bar")
      conso(Date.new(2026, 6, 30), 3_000, flow: "grocery")
      conso(Date.new(2026, 7, 31), 1_000, flow: "bar")
    end

    it "classe du plus gros au plus petit et donne les parts" do
      expect(bilan.canaux.map(&:flow)).to eq(%w[bar grocery])
      expect(bilan.canaux.first.amount_cents).to eq(7_000)
      expect(bilan.canaux.first.part).to be_within(0.01).of(70.0)
      expect(bilan.canaux.sum(&:part)).to be_within(0.01).of(100.0)
    end

    it "donne à chaque canal sa couleur, la même partout sur la page" do
      expect(bilan.canaux.first.couleur).to eq(described_class::COULEURS["bar"])
      expect(bilan.canaux.map(&:label)).to eq(["Bar", "Épicerie"])
    end

    # Une écriture sans canal existe (reprise historique, saisie libre) : elle
    # doit atterrir quelque part plutôt que de disparaître du total.
    it "range une écriture sans canal dans Divers" do
      conso(Date.new(2026, 7, 1), 500, flow: nil)

      expect(bilan.canaux.map(&:flow)).to include("other")
      expect(bilan.total_depense_cents).to eq(10_500)
    end
  end

  describe "les repères de lecture" do
    it "ne compte que les mois ouverts dans la moyenne" do
      conso(Date.new(2026, 7, 15), 10_000)
      conso(Date.new(2026, 8, 15), 20_000)

      expect(bilan.moyenne_mensuelle_cents).to eq(15_000)
      expect(bilan.mois_le_plus_charge.month).to eq(Date.new(2026, 8, 1))
      expect(bilan.plafond_cents).to eq(20_000)
    end

    it "ne divise pas par zéro sur un compte sans mouvement" do
      expect(bilan.moyenne_mensuelle_cents).to eq(0)
      expect(bilan.total_depense_cents).to eq(0)
      expect(bilan).not_to be_any
    end

    it "compte les règlements positivement, séparés des dépenses" do
      conso(Date.new(2026, 7, 15), 10_000)
      conso(Date.new(2026, 7, 20), -4_000, flow: nil, label: "Virement")

      expect(bilan.total_depense_cents).to eq(10_000)
      expect(bilan.total_regle_cents).to eq(4_000)
      expect(bilan.reglements.map(&:label)).to eq(["Virement"])
    end
  end

  describe "les articles" do
    let!(:biere) { CatalogItem.create!(name: "Moinette", channel: "bar") }
    let!(:cafe) { CatalogItem.create!(name: "Café", channel: "bar") }

    it "classe par montant et additionne les quantités" do
      conso(Date.new(2026, 6, 3), 400, item: biere, quantity: 2)
      conso(Date.new(2026, 7, 3), 600, item: biere, quantity: 3)
      conso(Date.new(2026, 7, 4), 150, item: cafe, quantity: 1)

      expect(bilan.articles.map(&:name)).to eq(["Moinette", "Café"])
      expect(bilan.articles.first.quantity).to eq(5.0)
      expect(bilan.articles.first.amount_cents).to eq(1_000)
    end

    it "se tait quand rien ne vient du catalogue" do
      conso(Date.new(2026, 7, 3), 17_000, flow: "charges", label: "Charges")

      expect(bilan.articles).to be_empty
    end
  end
end
