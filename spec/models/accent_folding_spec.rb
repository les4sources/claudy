require "rails_helper"

RSpec.describe AccentFolding do
  it "plie casse et accents de la même façon en Ruby et en SQL" do
    expect(described_class.fold("Néflier d'Allemagne — Chevêche")).to eq("neflier d'allemagne — cheveche")

    folded = ActiveRecord::Base.connection.select_value(
      "SELECT #{described_class.sql(ActiveRecord::Base.connection.quote('Néflier ÇÀ Œuf'))}"
    )
    expect(folded).to eq(described_class.fold("Néflier ÇÀ Œuf"))
  end

  it "échappe les jokers LIKE de la saisie" do
    expect(described_class.pattern("50%_é")).to eq("%50\\%\\_e%")
  end

  it "trouve une plante sans accents ni majuscules" do
    species = PlantSpecies.create!(name: "Néflier", latin_name: "Mespilus germanica")
    plant = Plant.create!(name: "Néflier Géant de Breda", plant_species: species)

    expect(Plant.search("neflier geant")).to contain_exactly(plant)
    expect(PlantSpecies.search("NEFLIER")).to contain_exactly(species)
  end
end
