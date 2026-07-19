require "rails_helper"

# Magasin clé/valeur des paramètres globaux ajustables sans redéploiement (issue #78).
RSpec.describe Setting do
  it "exige une clé unique" do
    described_class.create!(key: "foo", value: "1")
    expect(described_class.new(key: nil)).not_to be_valid
    expect(described_class.new(key: "foo", value: "2")).not_to be_valid
  end

  describe ".[]" do
    it "renvoie la valeur brute ou nil" do
      described_class.create!(key: "foo", value: "bar")
      expect(described_class["foo"]).to eq("bar")
      expect(described_class["absent"]).to be_nil
    end
  end

  describe ".integer" do
    it "retombe sur le défaut quand absent ou illisible" do
      expect(described_class.integer("absent", default: 42)).to eq(42)
      described_class.set("bad", "pas-un-nombre")
      expect(described_class.integer("bad", default: 7)).to eq(7)
    end

    it "convertit la valeur stockée en entier" do
      described_class.set("n", 45)
      expect(described_class.integer("n", default: 0)).to eq(45)
    end
  end

  describe ".set" do
    it "crée puis met à jour la même clé" do
      described_class.set("k", 1)
      described_class.set("k", 2)
      expect(described_class.where(key: "k").count).to eq(1)
      expect(described_class.integer("k", default: 0)).to eq(2)
    end
  end
end
