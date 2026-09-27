require "rails_helper"

# Epic #348, phase 7 — les fenêtres de récolte, par défaut sur l'espèce.
RSpec.describe PlantHarvestWindow, type: :model do
  let(:species) { PlantSpecies.create!(name: "Pommier") }

  def window(**attrs)
    species.harvest_windows.new({ part: "fruit", months: [9, 10] }.merge(attrs))
  end

  it "est valide avec une partie connue et des mois" do
    expect(window).to be_valid
  end

  it "refuse une partie inconnue" do
    expect(window(part: "bark")).not_to be_valid
  end

  it "nettoie les mois (cases du formulaire) et refuse une fenêtre vide ou hors calendrier" do
    w = window(months: ["10", "", "9", "10"])
    expect(w).to be_valid
    expect(w.months).to eq([9, 10])
    expect(w.months_label).to eq("sept., oct.")
    expect(window(months: [""])).not_to be_valid
    expect(window(months: [13])).not_to be_valid
  end

  it "n'a qu'une fenêtre par partie et par porteur" do
    window.save!
    expect(window(months: [8])).not_to be_valid
    expect(window(part: "flower", months: [4])).to be_valid
  end

  it "refuse un porteur hors de la liste fermée" do
    w = PlantHarvestWindow.new(part: "fruit", months: [9], owner_type: "User", owner_id: 1)
    expect(w).not_to be_valid
    expect(w.errors[:owner_type]).to be_present
  end

  it "trie par partie dans l'ordre de PARTS et filtre par mois" do
    fruit = window.tap(&:save!)
    flower = window(part: "flower", months: [4]).tap(&:save!)
    expect(species.harvest_windows.reload).to eq([flower, fruit])
    expect(PlantHarvestWindow.in_month(9)).to eq([fruit])
    expect(PlantHarvestWindow.for_part("flower")).to eq([flower])
    expect(fruit.part_label).to eq("Fruit")
  end
end
