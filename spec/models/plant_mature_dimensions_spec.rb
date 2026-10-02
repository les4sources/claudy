require "rails_helper"

# Les dimensions adultes d'une plante, pour la dessiner à maturité dans la vue
# 3D du relief : saisie de la plante, sinon espèce (texte libre), corrigée par
# la conduite.
RSpec.describe Plant, "#mature_dimensions" do
  let(:chestnut) { PlantSpecies.create!(name: "Châtaignier", latin_name: "Castanea sativa", height: "5-7 m / 15 m / 30 m / 20 à 35", spread: "8 m / 9 à 15m") }
  let(:walnut) { PlantSpecies.create!(name: "Noyer commun", latin_name: "Juglans regia", height: "15-30 m", spread: "5-10 m") }

  def plant(**attrs) = Plant.new({ name: "Essai", status: "on_plan" }.merge(attrs))

  it "lit la médiane d'un texte libre de dimension" do
    expect(described_class.typical_size("15-30 m")).to eq(22.5)
    expect(described_class.typical_size("5-7 m / 15 m / 30 m / 20 à 35")).to eq(17.5)
    expect(described_class.typical_size("2,5 m")).to eq(2.5)
    expect(described_class.typical_size("grand")).to be_nil
  end

  it "prend l'espèce pour un arbre libre" do
    expect(plant(plant_species: walnut, stratum: "tree").mature_dimensions).to eq(height: 22.5, spread: 7.5, source: "species")
  end

  it "plafonne une trogne et une cépée, quelle que soit l'espèce" do
    expect(plant(plant_species: chestnut, stratum: "pollard").mature_dimensions).to include(height: 5.0, spread: 4.0)
    coppice = plant(plant_species: chestnut, stratum: "coppice").mature_dimensions
    expect(coppice[:height]).to eq(7.0)
    expect(coppice[:spread]).to eq(5.4)
  end

  it "préfère ce qu'on a saisi pour la plante" do
    expect(plant(plant_species: walnut, mature_height: 12, mature_spread: 14).mature_dimensions).to eq(height: 12.0, spread: 14.0, source: "plant")
  end

  it "retombe sur la strate sans espèce ni saisie" do
    expect(plant(stratum: "shrub").mature_dimensions).to include(height: 2.5, spread: 1.9, source: "stratum")
  end

  it "refuse une taille absurde" do
    expect(plant(mature_height: 120)).not_to be_valid
    expect(plant(mature_spread: 0)).not_to be_valid
  end

  it "sait qu'une plante « Sur plan » est en projet" do
    expect(plant(status: "on_plan")).to be_planned
    expect(plant(status: "existing")).not_to be_planned
  end
end
