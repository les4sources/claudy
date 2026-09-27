require "rails_helper"

# Epic #348, phase 7 — le catalogue local des espèces et de leurs variétés.
RSpec.describe PlantSpecies, type: :model do
  it "exige un nom et le nettoie" do
    expect(PlantSpecies.new(name: "  ")).not_to be_valid
    expect(PlantSpecies.create!(name: "  Pommier   commun ").name).to eq("Pommier commun")
  end

  it "refuse un doublon sans égard à la casse, mais libère le nom d'une espèce supprimée" do
    first = PlantSpecies.create!(name: "Pommier")
    expect(PlantSpecies.new(name: "pommier")).not_to be_valid

    first.soft_delete!(validate: false)
    expect(PlantSpecies.new(name: "pommier")).to be_valid
  end

  it "nettoie les listes de la fiche botanique" do
    species = PlantSpecies.create!(name: "Néflier", exposure: ["Soleil", "", "Soleil", "Mi-ombre"], edible_parts: nil)
    expect(species.exposure).to eq(%w[Soleil Mi-ombre])
    expect(species.edible_parts).to eq([])
  end

  describe ".find_or_create_by_name!" do
    it "retrouve l'espèce quelle que soit la casse, sinon la crée" do
      existing = PlantSpecies.create!(name: "Pommier")
      expect(PlantSpecies.find_or_create_by_name!(" POMMIER ")).to eq(existing)

      created = PlantSpecies.find_or_create_by_name!("Néflier", latin_name: "Mespilus germanica")
      expect(created).to be_persisted
      expect(created.full_name).to eq("Néflier (Mespilus germanica)")
      expect(PlantSpecies.count).to eq(2)
    end

    it "refuse un nom vide" do
      expect { PlantSpecies.find_or_create_by_name!(" ") }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  it ".search cherche le nom et le nom latin" do
    apple = PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica")
    PlantSpecies.create!(name: "Poirier", latin_name: "Pyrus communis")
    expect(PlantSpecies.search("malus")).to eq([apple])
    expect(PlantSpecies.search("po").count).to eq(2)
    expect(PlantSpecies.search("").count).to eq(2)
  end
end

RSpec.describe PlantVariety, type: :model do
  let(:apple) { PlantSpecies.create!(name: "Pommier") }
  let(:pear) { PlantSpecies.create!(name: "Poirier") }

  it "est unique par espèce, sans égard à la casse" do
    apple.varieties.create!(name: "Reinette Hernaut")
    expect(apple.varieties.new(name: "reinette hernaut")).not_to be_valid
    expect(pear.varieties.new(name: "Reinette Hernaut")).to be_valid
  end

  it "find_or_create_by_name! travaille sous l'espèce" do
    existing = apple.varieties.create!(name: "Reinette Hernaut")
    expect(apple.find_or_create_variety!("REINETTE hernaut")).to eq(existing)

    created = apple.varieties.find_or_create_by_name!("Belle de Boskoop")
    expect(created.plant_species).to eq(apple)
    expect(created.full_name).to eq("Pommier Belle de Boskoop")
    expect(pear.find_or_create_variety!("Belle de Boskoop")).not_to eq(created)
  end

  it "est soft-deletée et versionnée" do
    variety = apple.varieties.create!(name: "Cox")
    variety.soft_delete!(validate: false)
    expect(PlantVariety.find_by(id: variety.id)).to be_nil
    expect(variety.versions).to be_present
    expect(apple.varieties.new(name: "Cox")).to be_valid
  end
end
