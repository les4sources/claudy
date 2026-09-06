require "rails_helper"

# Produit de buffet paramétré (epic #219, phase 6) : ce que Kitchen::ShoppingList
# lit pour calculer une liste de courses.
# == Schema Information
#
# Table name: kitchen_products
#
#  id                  :bigint           not null, primary key
#  active              :boolean          default(TRUE), not null
#  kinds               :jsonb            not null
#  name                :string           not null
#  note                :string
#  position            :integer
#  quantity_per_person :decimal(8, 2)    not null
#  unit                :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_kitchen_products_on_kinds  (kinds) USING gin
#
RSpec.describe KitchenProduct do
  def product(**attrs)
    described_class.create!({ name: "Fromage", unit: "g", quantity_per_person: 80,
                               kinds: %w[buffet_vege] }.merge(attrs))
  end

  describe "validations" do
    it "exige un nom, une unité connue et une quantité par personne positive" do
      expect(described_class.new(name: nil, unit: "g", quantity_per_person: 80)).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "kg", quantity_per_person: 80)).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "g", quantity_per_person: 0)).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "g", quantity_per_person: -1)).not_to be_valid
      expect(described_class.new(name: "Pain", unit: "piece", quantity_per_person: 0.5)).to be_valid
    end

    it "refuse un type hors nomenclature" do
      expect(described_class.new(name: "Pain", unit: "piece", quantity_per_person: 0.5,
                                  kinds: %w[repas])).not_to be_valid
    end

    it "nettoie les entrées vides laissées par les cases décochées du formulaire" do
      line = product(kinds: ["buffet_vege", "", nil])
      expect(line.kinds).to eq(["buffet_vege"])
    end
  end

  describe "portée active" do
    it "ne retient que les produits actifs" do
      actif  = product(active: true)
      inactif = product(name: "Jambon", active: false)

      expect(described_class.active).to include(actif)
      expect(described_class.active).not_to include(inactif)
    end
  end

  describe "portée for_kind" do
    it "ne retient que les produits dont les types incluent le type demandé" do
      fromage = product(kinds: %w[buffet_vege buffet_viande])
      jambon  = product(name: "Jambon", kinds: %w[buffet_viande])
      apero   = product(name: "Planche", kinds: %w[apero])

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
