require "rails_helper"

# Épic cycles — passer une action au cycle suivant : copie liée là-bas,
# issue « reportée » ici, refus propre sans cycle suivant.
RSpec.describe CycleActions::DeferService do
  let(:human) { Human.create!(name: "Alice", cycle_active: true, roles_enabled: true) }
  let(:cycle) { Cycle.create!(name: "C1", start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 6, 30)) }
  let(:action) { CycleAction.create!(human: human, cycle: cycle, label: "Réparer la clôture", hours: 3, category: :ponctuelle) }

  context "sans cycle suivant" do
    it "refuse avec un message clair et ne touche à rien" do
      service = described_class.new(cycle_action: action)
      expect(service.run).to be(false)
      expect(service.error_message).to eq(described_class::NO_NEXT_CYCLE)
      expect(action.reload.outcome).to be_nil
      expect(CycleAction.count).to eq(1)
    end
  end

  context "avec un cycle suivant" do
    let!(:next_cycle) { Cycle.create!(name: "C2", start_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 8, 31)) }

    it "crée une copie liée et marque l'origine reportée" do
      service = described_class.new(cycle_action: action)
      expect(service.run).to be(true)

      expect(action.reload).to be_outcome_deferred
      copy = service.copy
      expect(copy.cycle).to eq(next_cycle)
      expect(copy.human).to eq(human)
      expect(copy.label).to eq("Réparer la clôture")
      expect(copy.hours).to eq(3)
      expect(copy.deferred_from).to eq(action)
      expect(copy.deferral_count).to eq(1)
      expect(copy).not_to be_completed
      expect(action.deferred_to).to eq(copy)
    end

    it "remet une action du sas « reportée » en ponctuelle dans le suivant" do
      action.update!(category: :reportee)
      described_class.new(cycle_action: action).run!
      expect(action.reload.deferred_to.category).to eq("ponctuelle")
    end

    it "cumule le compteur de reports d'un cycle à l'autre" do
      third = Cycle.create!(name: "C3", start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 10, 31))
      described_class.new(cycle_action: action).run!
      copy = action.reload.deferred_to
      described_class.new(cycle_action: copy).run!
      expect(copy.reload.deferred_to.deferral_count).to eq(2)
      expect(copy.deferred_to.cycle).to eq(third)
    end

    it "refuse si le cycle est clos" do
      cycle.update!(closed_at: Time.current)
      service = described_class.new(cycle_action: action)
      expect(service.run).to be(false)
      expect(service.error_message).to eq(described_class::CLOSED)
    end

    it "refuse une action déjà tranchée" do
      action.update!(outcome: :dropped)
      expect(described_class.new(cycle_action: action).run).to be(false)
    end
  end
end
