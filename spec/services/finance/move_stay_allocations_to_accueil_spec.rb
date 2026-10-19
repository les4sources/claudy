require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La reprise des affectations de séjour faites avant la règle « un séjour va
# sur le pôle Accueil » (Michael, 2026-10-19).
RSpec.describe Finance::MoveStayAllocationsToAccueil do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:cash_account) { build_cash_account(entity, bank_account) }
  let(:hebergement) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let(:dons) { build_general_account(code: "730000", name: "Dons", klass: 7, nature: "revenue") }
  let!(:accueil) { Team.create!(name: "Pôle Accueil") }
  let(:technique) { Team.create!(name: "Service Technique") }
  let(:customer) { Customer.create!(first_name: "Jeanne", last_name: "Dupont", email: "jeanne@example.test") }
  let(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 6, 12), departure_date: Date.new(2026, 6, 15))
  end
  let(:entry) { build_cash_entry(cash_account, amount_cents: 30_000) }
  let!(:part_sejour) do
    entry.cash_allocations.create!(general_account: hebergement, amount_cents: 20_000, legal_entity: entity,
                                   team: nil, document: stay)
  end
  let!(:part_don) { allocate(entry, account: dons, amount_cents: 10_000, entity: entity, team: technique) }

  before { Accounting::PostCashEntry.new(cash_entry: entry).run! }

  it "ne fait que compter en simulation" do
    report = nil
    expect { report = described_class.new(dry_run: true).run! }.not_to change(JournalEntry, :count)

    expect(report.moved.map(&:cash_entry)).to eq([entry])
    expect(report.allocations).to eq([part_sejour])
    expect(part_sejour.reload.team).to be_nil
  end

  it "passe les parts du séjour sur l'Accueil, contre-passe puis repasse, sans toucher aux autres parts" do
    report = described_class.new(dry_run: false).run!

    expect(report.refused).to be_empty
    expect(part_sejour.reload.team).to eq(accueil)
    expect(part_don.reload.team).to eq(technique)
    expect(entry.reload).to be_posted
    expect(JournalLine.where(general_account: hebergement).group(:team_id).sum("credit_cents - debit_cents"))
      .to eq(nil => 0, accueil.id => 20_000)
  end

  it "ne retrouve plus rien la seconde fois" do
    described_class.new(dry_run: false).run!

    expect(described_class.new(dry_run: true).run!.allocations).to be_empty
  end

  it "refuse une ligne d'un mois arrêté et la laisse telle quelle" do
    MonthClosing.create!(period_month: Date.new(2026, 6, 1), closed_at: Time.current)

    expect(described_class.new(dry_run: true).run!.refused.map(&:error)).to eq(["juin 2026 est arrêté"])
    report = described_class.new(dry_run: false).run!

    expect(report.refused.size).to eq(1)
    expect(part_sejour.reload.team).to be_nil
  end
end
