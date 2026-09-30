require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Les charges fixes (2026-09-30) : une règle écrite une fois, dont les
# occurrences se déduisent toujours de la première échéance.
RSpec.describe RecurringExpense do
  include FinanceBuilders

  let(:entity) { build_legal_entity }

  def expense(**attributes)
    described_class.new({ legal_entity: entity, label: "Voo", amount_cents: 6_776,
                          frequency: "monthly", first_due_on: Date.new(2026, 1, 31) }.merge(attributes))
  end

  it "déduit chaque occurrence de la première : un 31 ne dérive pas en 28 pour toujours" do
    expect(expense.occurrences_between(Date.new(2026, 1, 1), Date.new(2026, 4, 30)))
      .to eq([Date.new(2026, 1, 31), Date.new(2026, 2, 28), Date.new(2026, 3, 31), Date.new(2026, 4, 30)])
  end

  it "ne rend que les occurrences de la fenêtre, et s'arrête à la date de fin" do
    trimestrielle = expense(frequency: "quarterly", first_due_on: Date.new(2025, 1, 15), ends_on: Date.new(2026, 7, 31))

    expect(trimestrielle.occurrences_between(Date.new(2026, 1, 1), Date.new(2026, 12, 31)))
      .to eq([Date.new(2026, 1, 15), Date.new(2026, 4, 15), Date.new(2026, 7, 15)])
  end

  it "donne la prochaine échéance" do
    # Septembre n'a que 30 jours : le prélèvement « du 31 » y tombe le 30.
    expect(expense.next_due_on(Date.new(2026, 9, 30))).to eq(Date.new(2026, 9, 30))
    expect(expense.next_due_on(Date.new(2026, 10, 1))).to eq(Date.new(2026, 10, 31))
  end

  it "lit un montant saisi à la belge" do
    record = expense(amount_cents: nil)
    record.amount = "1 067,76"

    expect(record.amount_cents).to eq(106_776)
  end

  it "compte ce que la charge coûte sur un an" do
    expect(expense.yearly_cents).to eq(81_312)
    expect(expense(frequency: "quarterly").yearly_cents).to eq(27_104)
    expect(expense(frequency: "yearly").yearly_cents).to eq(6_776)
  end

  it "refuse un montant nul et une fin avant la première échéance" do
    record = expense(amount_cents: 0, ends_on: Date.new(2025, 12, 31))

    expect(record).not_to be_valid
    expect(record.errors[:amount_cents]).to be_present
    expect(record.errors[:ends_on]).to be_present
  end
end
