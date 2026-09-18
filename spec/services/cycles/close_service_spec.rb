require "rails_helper"

# Épic cycles — clôture : chaque action vivante reçoit une issue, rituelles et
# reportées repartent dans le cycle suivant, le cycle est verrouillé.
RSpec.describe Cycles::CloseService do
  let(:human) { Human.create!(name: "Bob", cycle_active: true, roles_enabled: true) }
  let(:cycle) { Cycle.create!(name: "C1", start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 6, 30)) }

  def action(label, **attrs)
    CycleAction.create!({ human: human, cycle: cycle, label: label, hours: 1, category: :ponctuelle }.merge(attrs))
  end

  it "refuse sans cycle suivant" do
    action("x")
    service = described_class.new(cycle: cycle)
    expect(service.run).to be(false)
    expect(service.error_message).to eq(described_class::NO_NEXT_CYCLE)
    expect(cycle.reload).to be_open
  end

  context "avec un cycle suivant" do
    let!(:next_cycle) { Cycle.create!(name: "C2", start_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 8, 31)) }

    it "tranche tout, recrée rituelles et reportées, verrouille le cycle" do
      done = action("faite", completed: true)
      rituelle_done = action("rituelle faite", category: :rituelle, completed: true)
      rituelle_pending = action("rituelle pas faite", category: :rituelle)
      reportee = action("en attente", category: :reportee)
      dropped = action("oubliée")
      already = action("déjà archivée", archived_at: Time.current, outcome: :dropped)

      service = described_class.new(cycle: cycle)
      expect(service.run).to be(true)

      expect(cycle.reload).to be_closed
      expect(done.reload).to be_outcome_done
      expect(rituelle_done.reload).to be_outcome_done
      expect(rituelle_pending.reload).to be_outcome_deferred
      expect(reportee.reload).to be_outcome_deferred
      expect(dropped.reload).to be_outcome_dropped
      expect(already.reload).to be_outcome_dropped

      copies = next_cycle.cycle_actions.order(:id)
      expect(copies.map(&:label)).to contain_exactly("rituelle faite", "rituelle pas faite", "en attente")
      expect(copies.find_by(label: "en attente").category).to eq("ponctuelle")
      expect(copies.find_by(label: "en attente").deferral_count).to eq(1)
      expect(copies.find_by(label: "rituelle faite").deferral_count).to eq(0)
      expect(copies.all? { |c| !c.completed? && c.deferred_from.present? }).to be(true)

      expect(service.summary).to eq({ done: 2, deferred: 2, dropped: 1 })
    end

    it "refuse un cycle déjà clos" do
      cycle.update!(closed_at: Time.current)
      expect(described_class.new(cycle: cycle).run).to be(false)
    end
  end

  # Issue #338 — une action répétée ne fait passer au cycle suivant que ce qui
  # reste à faire ; une rituelle entièrement faite repart au complet.
  describe "les occurrences (issue #338)" do
    let!(:next_cycle) { Cycle.create!(name: "C2", start_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 8, 31)) }

    it "ne recrée que le reste d'une rituelle partiellement faite" do
      action = CycleAction.create!(human: human, cycle: cycle, label: "Batchcooking",
                                   category: :rituelle, unit_hours: 11, occurrences: 3,
                                   completed_occurrences: 2)
      described_class.new(cycle: cycle).run

      copy = action.reload.deferred_to
      expect(copy.occurrences).to eq(1)
      expect(copy.unit_hours).to eq(11)
      expect(copy.hours).to eq(11)
      expect(copy.completed_occurrences).to eq(0)
    end

    it "relance une rituelle entièrement faite sur son nombre de fois complet" do
      action = CycleAction.create!(human: human, cycle: cycle, label: "Batchcooking",
                                   category: :rituelle, unit_hours: 11, occurrences: 3,
                                   completed_occurrences: 3)
      described_class.new(cycle: cycle).run

      copy = action.reload.deferred_to
      expect(copy.occurrences).to eq(3)
      expect(copy.hours).to eq(33)
    end
  end
end
