require "rails_helper"

# Epic #330, phase 4 — copier une action au cycle suivant. Là où la flèche
# DÉPLACE, la copie DUPLIQUE : l'origine reste dans son cycle, intacte. Un second
# appel retire la copie au lieu d'en créer une deuxième (décision 6).
RSpec.describe CycleActions::CopyService do
  let(:human) { Human.create!(name: "Alice", cycle_active: true, roles_enabled: true) }
  let(:cycle) { Cycle.create!(name: "C1", start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 6, 30)) }
  let(:action) do
    CycleAction.create!(human: human, cycle: cycle, label: "Nettoyer le four", hours: 4, category: :rituelle,
                        economic: true, actual_hours: 3, completed: true, deferral_count: 2)
  end

  context "sans cycle suivant" do
    it "refuse avec un message clair et ne crée rien" do
      service = described_class.new(cycle_action: action)
      expect(service.run).to be(false)
      expect(service.error_message).to eq(described_class::NO_NEXT_CYCLE)
      expect(CycleAction.count).to eq(1)
    end
  end

  context "avec un cycle suivant" do
    let!(:next_cycle) { Cycle.create!(name: "C2", start_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 8, 31)) }

    it "crée la copie dans le cycle suivant avec l'estimé et un avancement remis à zéro" do
      service = described_class.new(cycle_action: action)
      expect(service.run).to be(true)
      expect(service).to be_copied

      copy = service.copy
      expect(copy.cycle).to eq(next_cycle)
      expect(copy.human).to eq(human)
      expect(copy.label).to eq("Nettoyer le four")
      expect(copy).to be_rituelle
      expect(copy.hours).to eq(4)
      expect(copy).to be_economic
      expect(copy.actual_hours).to eq(0)
      expect(copy).not_to be_completed
      expect(copy.outcome).to be_nil
      expect(copy.archived_at).to be_nil
      expect(copy.deferral_count).to eq(0)
      expect(copy.deferred_from_id).to be_nil
      expect(copy.copied_from).to eq(action)
      expect(action.reload.copy_in_next_cycle).to eq(copy)
    end

    it "laisse l'origine intacte dans son cycle" do
      described_class.new(cycle_action: action).run
      action.reload
      expect(action.cycle).to eq(cycle)
      expect(action.outcome).to be_nil
      expect(action).to be_completed
      expect(action.actual_hours).to eq(3)
      expect(action.deferred_to).to be_nil
    end

    it "garde le détail des occurrences et les rouvre toutes" do
      repeated = CycleAction.create!(human: human, cycle: cycle, label: "Batchcooking", unit_hours: 2, occurrences: 3,
                                     completed_occurrences: 2, category: :rituelle)
      copy = described_class.new(cycle_action: repeated).tap(&:run).copy
      expect(copy.unit_hours).to eq(2)
      expect(copy.occurrences).to eq(3)
      expect(copy.completed_occurrences).to eq(0)
      expect(copy.hours).to eq(6)
    end

    it "place la copie en fin de sa catégorie dans le cycle cible" do
      CycleAction.create!(human: human, cycle: next_cycle, label: "Déjà là", category: :rituelle, position: 4)
      copy = described_class.new(cycle_action: action).tap(&:run).copy
      expect(copy.position).to eq(5)
    end

    it "retire la copie au second appel au lieu d'en créer une deuxième" do
      first = described_class.new(cycle_action: action).tap(&:run).copy

      second = described_class.new(cycle_action: action)
      expect(second.run).to be(true)
      expect(second).not_to be_copied
      expect(second.target_cycle).to eq(next_cycle)

      expect(CycleAction.where(copied_from_id: action.id)).to be_empty
      expect(CycleAction.unscoped.find(first.id).deleted_at).to be_present
      expect(action.reload.copy_in_next_cycle).to be_nil
    end

    it "recrée une copie au troisième appel" do
      3.times { described_class.new(cycle_action: action).run }
      expect(CycleAction.where(copied_from_id: action.id).count).to eq(1)
    end

    it "refuse une seconde copie vivante au niveau de la base" do
      described_class.new(cycle_action: action).run
      expect {
        CycleAction.create!(human: human, cycle: next_cycle, label: "Doublon", category: :rituelle, copied_from: action)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "refuse sur un cycle clos" do
      cycle.update!(closed_at: Time.current)
      service = described_class.new(cycle_action: action)
      expect(service.run).to be(false)
      expect(service.error_message).to eq(described_class::CLOSED)
      expect(CycleAction.where(copied_from_id: action.id)).to be_empty
    end
  end
end
