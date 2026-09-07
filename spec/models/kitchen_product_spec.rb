require "rails_helper"

# Produit de buffet paramétré (epic #219, phase 6) : ce que Kitchen::ShoppingList
# lit pour calculer une liste de courses. La quantité est PAR TYPE — un seul
# « Fromages » sert le buffet végé et le buffet avec viande, chacun à sa dose.
# == Schema Information
#
# Table name: kitchen_products
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  name       :string           not null
#  note       :string
#  position   :integer
#  quantities :jsonb            not null
#  unit       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_kitchen_products_on_quantities  (quantities) USING gin
#
RSpec.describe KitchenProduct do
  def product(**attrs)
    described_class.create!({ name: "Fromage", unit: "g",
                              quantities: { "buffet_vege" => "80" } }.merge(attrs))
  end

  describe "validations" do
    it "exige un nom, une unité connue et au moins une quantité positive" do
      expect(described_class.new(name: nil, unit: "g", quantities: { "buffet_vege" => "80" })).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "kg", quantities: { "buffet_vege" => "80" })).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "g", quantities: {})).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "g", quantities: { "buffet_vege" => "0" })).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "g", quantities: { "buffet_vege" => "-1" })).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "g", quantities: { "buffet_vege" => "oui" })).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "piece", quantities: { "buffet_vege" => "0.5" })).to be_valid
    end

    it "ignore un type hors nomenclature au lieu de le stocker" do
      line = described_class.new(name: "Pain", unit: "piece",
                                 quantities: { "repas" => "1", "apero" => "0.5" })

      expect(line).to be_valid
      expect(line.quantities).to eq("apero" => "0.5")
    end

    it "écarte les champs laissés vides par le formulaire" do
      line = product(quantities: { "buffet_vege" => "80", "buffet_viande" => "", "apero" => nil })

      expect(line.quantities).to eq("buffet_vege" => "80")
    end

    it "accepte la virgule décimale d'un clavier belge" do
      line = product(unit: "piece", quantities: { "buffet_vege" => "0,5" })

      expect(line.quantity_for("buffet_vege")).to eq(0.5)
    end
  end

  describe "#quantity_for" do
    it "donne une quantité différente selon le type, et rien hors de ses types" do
      fromages = product(name: "Fromages", quantities: { "buffet_vege" => "80", "buffet_viande" => "50" })

      expect(fromages.quantity_for("buffet_vege")).to eq(80)
      expect(fromages.quantity_for("buffet_viande")).to eq(50)
      expect(fromages.quantity_for("apero")).to be_nil
    end
  end

  describe "#kinds et #quantity_label" do
    it "liste les types dans l'ordre canonique et libelle chaque quantité" do
      fromages = product(name: "Fromages", quantities: { "apero" => "30", "buffet_vege" => "80" })

      expect(fromages.kinds).to eq(%w[buffet_vege apero])
      expect(fromages.quantity_label("buffet_vege")).to eq("80 g")
      expect(fromages.quantity_label("buffet_viande")).to be_nil
    end

    it "retire le zéro décimal inutile et accorde « pièce »" do
      pain = product(name: "Pain", unit: "piece",
                     quantities: { "buffet_vege" => "0.5", "buffet_viande" => "2.00" })

      expect(pain.quantity_label("buffet_vege")).to eq("0,5 pièce")
      expect(pain.quantity_label("buffet_viande")).to eq("2 pièces")
    end
  end

  describe "portée active" do
    it "ne retient que les produits actifs" do
      actif   = product(active: true)
      inactif = product(name: "Jambon", active: false)

      expect(described_class.active).to include(actif)
      expect(described_class.active).not_to include(inactif)
    end
  end

  describe "portée for_kind" do
    it "ne retient que les produits qui portent une quantité pour ce type" do
      fromage = product(quantities: { "buffet_vege" => "80", "buffet_viande" => "50" })
      jambon  = product(name: "Jambon", quantities: { "buffet_viande" => "60" })
      apero   = product(name: "Planche", quantities: { "apero" => "40" })

      expect(described_class.for_kind("buffet_vege")).to contain_exactly(fromage)
      expect(described_class.for_kind("buffet_viande")).to contain_exactly(fromage, jambon)
      expect(described_class.for_kind("apero")).to contain_exactly(apero)
    end
  end

  describe "portée ordered" do
    it "trie par position puis par nom, les positions nulles en dernier" do
      sans_position = product(name: "Sans position", position: nil)
      deuxieme      = product(name: "Deuxième", position: 2)
      premier       = product(name: "Premier", position: 1)

      expect(described_class.ordered.to_a).to eq([premier, deuxieme, sans_position])
    end
  end

  it "est actif par défaut" do
    expect(described_class.new.active).to be(true)
  end
end
