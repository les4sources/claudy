require "rails_helper"

# Paramètres de l'offre de cuisine (epic #219, phase 2).
RSpec.describe Kitchen::Config do
  describe "défauts d'une installation neuve" do
    it "propose les trois familles" do
      expect(described_class.enabled?("repas")).to be(true)
      expect(described_class.enabled?("buffet")).to be(true)
      expect(described_class.enabled?("apero")).to be(true)
      expect(described_class.enabled_kinds).to eq(MealOrder::KINDS)
    end

    it "porte les plafonds et délais d'usage" do
      expect(described_class.max_people("repas")).to eq(25)
      expect(described_class.max_people("buffet")).to be_nil
      expect(described_class.lead_days("repas")).to eq(7)
      expect(described_class.lead_days("apero")).to eq(5)
    end

    it "n'a aucun responsable par défaut et connaît l'email de coordination" do
      expect(described_class.default_human("repas")).to be_nil
      expect(described_class.coordinator_email).to eq("malau@les4sources.be")
    end
  end

  describe "après paramétrage" do
    it "retire une famille de l'offre sans toucher aux autres" do
      Setting.set("kitchen.apero.enabled", "0")

      expect(described_class.enabled?("apero")).to be(false)
      expect(described_class.enabled_kinds).to eq(%w[repas trio buffet_vege buffet_viande])
    end

    it "lit le responsable par défaut" do
      steph = Human.create!(name: "Stéphanie", email: "steph@les4sources.be")
      Setting.set("kitchen.repas.default_human_id", steph.id)

      expect(described_class.default_human("repas")).to eq(steph)
    end

    it "distingue un plafond effacé d'un plafond jamais posé" do
      Setting.set("kitchen.repas.max_people", "")
      expect(described_class.max_people("repas")).to be_nil

      Setting.set("kitchen.repas.max_people", "40")
      expect(described_class.max_people("repas")).to eq(40)
    end
  end
end
