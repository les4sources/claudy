require "rails_helper"

# Epic #330, phase 5 — les pôles proposés dans le formulaire d'une action.
RSpec.describe TeamDecorator do
  describe ".grouped_options" do
    it "groupe par nature dans l'ordre de Team::KINDS, trie par nom, et garde les non classés en dernier" do
      Team.create!(name: "Transmission")
      Team.create!(name: "Pôle Cuisine", kind: "analytic")
      Team.create!(name: "Pôle Boulangerie", kind: "analytic")
      Team.create!(name: "Comptabilité", kind: "support")
      Team.create!(name: "Pôle Accueil", kind: "economic")

      options = described_class.grouped_options(Team.all)

      expect(options.map(&:first)).to eq(["Pôle analytique", "Pôle économique", "Service support", "Non classé"])
      expect(options.first.last.map(&:first)).to eq(["Pôle Boulangerie", "Pôle Cuisine"])
      expect(options.last.last.map(&:first)).to eq(["Transmission"])
    end

    it "omet les groupes vides" do
      Team.create!(name: "Pôle Accueil", kind: "economic")

      expect(described_class.grouped_options(Team.all).map(&:first)).to eq(["Pôle économique"])
    end
  end
end
