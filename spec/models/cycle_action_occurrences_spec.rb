require "rails_helper"

# Issue #338 — une action de cycle peut se répéter : on saisit la durée d'UNE
# fois et le nombre de fois, le système calcule le total. `hours` reste le total
# engagé — c'est l'invariant que tout le reste de l'app additionne.
RSpec.describe CycleAction, "occurrences (issue #338)" do
  let(:human) { Human.create!(name: "Stéphanie", cycle_active: true, roles_enabled: true) }
  let(:cycle) { Cycle.create!(name: "C1", start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 6, 30)) }

  def build_action(**attrs)
    described_class.create!({ human: human, cycle: cycle, label: "Batchcooking", category: :ponctuelle }.merge(attrs))
  end

  describe "le total engagé" do
    it "vaut la durée d'une fois × le nombre de fois" do
      action = build_action(unit_hours: 11, occurrences: 3)
      expect(action.hours).to eq(33)
      expect(action).to be_multiple
    end

    it "vaut la durée unitaire quand l'action ne se fait qu'une fois" do
      action = build_action(unit_hours: 2.5)
      expect(action.hours).to eq(2.5)
      expect(action.occurrences).to eq(1)
      expect(action).not_to be_multiple
    end

    it "dérive la durée unitaire quand seul le total est fourni (saisie ancienne, API)" do
      action = build_action(hours: 4)
      expect(action.unit_hours).to eq(4)
      expect(action.occurrences).to eq(1)
      expect(action.hours).to eq(4)
    end

    it "se recalcule quand on change le nombre de fois" do
      action = build_action(unit_hours: 11, occurrences: 3)
      action.update!(occurrences: 4)
      expect(action.hours).to eq(44)
    end

    it "se recalcule quand on change la durée d'une fois" do
      action = build_action(unit_hours: 11, occurrences: 3)
      action.update!(unit_hours: 10)
      expect(action.hours).to eq(30)
    end

    it "ne bouge pas quand on sauvegarde sans toucher aux heures" do
      action = build_action(hours: 10, occurrences: 3)
      expect(action.hours).to eq(10)
      action.update!(label: "Autre chose")
      expect(action.reload.hours).to eq(10)
    end
  end

  describe "la case « fait »" do
    it "se déduit des occurrences cochées" do
      action = build_action(unit_hours: 11, occurrences: 3)
      expect(action).not_to be_completed

      action.update!(completed_occurrences: 2)
      expect(action.reload).not_to be_completed

      action.update!(completed_occurrences: 3)
      expect(action.reload).to be_completed
    end

    it "reste pilotable par la case unique (toggle_completed, settle, API)" do
      action = build_action(unit_hours: 2)
      action.update!(completed: true)
      expect(action.reload.completed_occurrences).to eq(1)

      action.update!(completed: false)
      expect(action.reload.completed_occurrences).to eq(0)
      expect(action.reload).not_to be_completed
    end

    it "coche toutes les occurrences quand on marque l'action faite d'un bloc" do
      action = build_action(unit_hours: 11, occurrences: 3)
      action.update!(completed: true)
      expect(action.reload.completed_occurrences).to eq(3)
      expect(action.completed_hours).to eq(33)
    end
  end

  describe "les heures faites" do
    it "comptent les occurrences cochées" do
      action = build_action(unit_hours: 11, occurrences: 3, completed_occurrences: 2)
      expect(action.completed_hours).to eq(22)
      expect(action.remaining_occurrences).to eq(1)
    end

    it "valent le total pour une action « une fois » cochée, 0 sinon" do
      action = build_action(unit_hours: 3)
      expect(action.completed_hours).to eq(0)
      action.update!(completed: true)
      expect(action.reload.completed_hours).to eq(3)
    end
  end

  describe "les bornes" do
    it "refuse un nombre de fois nul ou négatif" do
      action = described_class.new(human: human, cycle: cycle, label: "X", category: :ponctuelle, occurrences: 0)
      expect(action).not_to be_valid
      expect(action.errors[:occurrences]).to be_present
    end

    it "refuse plus d'occurrences faites que d'occurrences" do
      action = build_action(unit_hours: 1, occurrences: 2)
      action.completed_occurrences = 5
      expect(action).not_to be_valid
      expect(action.errors[:completed_occurrences]).to be_present
    end

    it "ramène les occurrences faites dans les clous quand on réduit le nombre de fois" do
      action = build_action(unit_hours: 11, occurrences: 3, completed_occurrences: 3)
      action.update!(occurrences: 2)
      expect(action.reload.completed_occurrences).to eq(2)
      expect(action.hours).to eq(22)
    end
  end

  describe "ce qui passe au cycle suivant" do
    it "n'emporte que le reste à faire" do
      action = build_action(unit_hours: 11, occurrences: 3, completed_occurrences: 2)
      expect(action.carry_over_occurrences).to eq(1)
    end

    it "repart au complet quand tout est fait (une rituelle qu'on relance)" do
      action = build_action(unit_hours: 11, occurrences: 3, completed_occurrences: 3, category: :rituelle)
      expect(action.carry_over_occurrences).to eq(3)
    end

    it "emporte au moins une fois quand rien n'est fait" do
      action = build_action(unit_hours: 11, occurrences: 3)
      expect(action.carry_over_occurrences).to eq(3)
    end
  end
end
