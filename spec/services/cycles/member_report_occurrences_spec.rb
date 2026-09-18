require "rails_helper"

# Issue #338 — le bilan d'un membre compte les occurrences cochées, y compris
# sur une action encore en jeu ou déjà tranchée. L'invariant qui tient tout :
# fait + reporté + abandonné + à trancher == planifié.
RSpec.describe Cycles::MemberReport, "occurrences (issue #338)" do
  let(:human) { Human.create!(name: "Stéphanie", cycle_active: true, roles_enabled: true) }
  let(:cycle) { Cycle.create!(name: "C1", start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 6, 30)) }
  let!(:next_cycle) { Cycle.create!(name: "C2", start_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 8, 31)) }

  def build_action(**attrs)
    CycleAction.create!({ human: human, cycle: cycle, label: "Batchcooking", category: :ponctuelle }.merge(attrs))
  end

  def report = described_class.new(human: human, cycle: cycle)

  def invariant(r)
    r.done_hours + r.deferred_hours + r.dropped_hours + r.pending_hours
  end

  it "compte les occurrences faites d'une action encore en jeu" do
    build_action(unit_hours: 11, occurrences: 3, completed_occurrences: 2)
    r = report
    expect(r.planned_hours).to eq(33)
    expect(r.done_hours).to eq(22)
    expect(r.pending_hours).to eq(11)
    expect(invariant(r)).to eq(r.planned_hours)
  end

  it "laisse le reste en « reporté » quand l'action passe au cycle suivant" do
    action = build_action(unit_hours: 11, occurrences: 3, completed_occurrences: 2)
    expect(CycleActions::DeferService.new(cycle_action: action).run).to be(true)

    r = report
    expect(r.planned_hours).to eq(33)
    expect(r.done_hours).to eq(22)
    expect(r.deferred_hours).to eq(11)
    expect(invariant(r)).to eq(r.planned_hours)

    copy = action.reload.deferred_to
    expect(copy.occurrences).to eq(1)
    expect(copy.unit_hours).to eq(11)
    expect(copy.hours).to eq(11)
    expect(copy.completed_occurrences).to eq(0)
  end

  it "laisse le reste en « abandonné » quand l'action est archivée" do
    action = build_action(unit_hours: 11, occurrences: 3, completed_occurrences: 1)
    action.archive!

    r = report
    expect(r.done_hours).to eq(11)
    expect(r.dropped_hours).to eq(22)
    expect(invariant(r)).to eq(r.planned_hours)
  end

  it "ne change rien aux chiffres d'une action « une fois »" do
    build_action(label: "Tondre", hours: 2, completed: true)
    build_action(label: "Peindre", hours: 4)

    r = report
    expect(r.planned_hours).to eq(6)
    expect(r.done_hours).to eq(2)
    expect(r.pending_hours).to eq(4)
    expect(invariant(r)).to eq(r.planned_hours)
  end
end
