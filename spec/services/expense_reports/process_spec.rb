require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #241, phase 1 — le passage en traitement. C'est LE moment où la note
# devient un document comptable : numéro de pièce, écriture d'achat, et plus
# rien de ce qui décrit la dépense ne bouge.
RSpec.describe ExpenseReports::Process do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:supplier_account) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:expense_account) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let(:team) { Team.create!(name: "Pôle Technique") }
  let(:human) { Human.create!(name: "Sébastien Test", iban: "BE68539007547034") }

  def build_report(kind: "expenses")
    report = ExpenseReport.create!(kind: kind, human: human, legal_entity: entity,
                                   submitted_on: Date.new(2026, 6, 1))
    report.expense_lines.create!(spent_on: Date.new(2026, 5, 28), label: "Visserie",
                                 supplier_name: "Brico Yvoir", amount_cents: 2_490,
                                 general_account: expense_account, team: team)
    report.expense_lines.create!(spent_on: Date.new(2026, 5, 30), label: "Terreau",
                                 amount_cents: 6_250, general_account: expense_account)
    report.reload
  end

  it "attribue la référence, génère l'écriture et fige la note" do
    report = build_report

    described_class.new(expense_report: report, processed_on: Date.new(2026, 6, 10)).run!

    report.reload
    expect(report.status).to eq("processing")
    expect(report.reference).to eq("NF-2026-001")
    expect(report.sequence_number).to eq(1)
    expect(report.fiscal_year).to eq(fiscal_year)
    expect(report.posted_at).to be_present

    entry = report.journal_entry
    expect(entry.journal).to eq("purchases")
    expect(entry.entry_date).to eq(Date.new(2026, 6, 10))
    expect(entry.journal_lines.sum(&:debit_cents)).to eq(8_740)
    expect(entry.journal_lines.sum(&:credit_cents)).to eq(8_740)
  end

  it "porte la dette au 440000 avec le tiers du bénéficiaire" do
    report = build_report
    described_class.new(expense_report: report).run!

    credit = report.reload.journal_entry.journal_lines.find { |line| line.credit_cents.positive? }
    expect(credit.general_account.code).to eq("440000")
    expect(credit.third_party.human).to eq(human)
  end

  it "garde le pôle de chaque ligne au débit — c'est ce qui fait l'analytique" do
    report = build_report
    described_class.new(expense_report: report).run!

    debits = report.reload.journal_entry.journal_lines.select { |line| line.debit_cents.positive? }
    expect(debits.size).to eq(2)
    expect(debits.map { |line| line.team&.name }).to contain_exactly("Pôle Technique", nil)
  end

  it "est idempotent : repasser la même note ne crée pas une seconde écriture" do
    report = build_report
    described_class.new(expense_report: report).run!

    expect { Accounting::PostExpenseReport.new(expense_report: report.reload).run! }
      .not_to change { JournalEntry.where(source: report).count }
  end

  it "refuse une note sans ligne" do
    report = ExpenseReport.create!(human: human, legal_entity: entity)

    expect { described_class.new(expense_report: report).run! }
      .to raise_error(described_class::NoLines)
  end

  it "refuse une note qui n'est pas enregistrée" do
    report = build_report
    described_class.new(expense_report: report).run!

    expect { described_class.new(expense_report: report.reload).run! }
      .to raise_error(described_class::BadStatus)
  end

  it "refuse de comptabiliser hors d'un exercice ouvert" do
    report = build_report

    expect { described_class.new(expense_report: report, processed_on: Date.new(2029, 1, 5)).run! }
      .to raise_error(described_class::MissingFiscalYear)
  end

  it "tient deux séquences distinctes pour les frais et les missions" do
    described_class.new(expense_report: build_report).run!
    mission = build_report(kind: "mileage")
    described_class.new(expense_report: mission).run!

    expect(mission.reload.reference).to eq("NM-2026-001")
    described_class.new(expense_report: build_report).run!
    expect(ExpenseReport.where(kind: "expenses").order(:sequence_number).pluck(:reference))
      .to eq(%w[NF-2026-001 NF-2026-002])
  end

  it "ne laisse pas deux notes prendre le même numéro" do
    premiere = build_report
    seconde = build_report

    described_class.new(expense_report: premiere).run!
    described_class.new(expense_report: seconde).run!

    expect([premiere.reload.reference, seconde.reload.reference].uniq.size).to eq(2)
    expect(ExpenseReport.where.not(sequence_number: nil).pluck(:sequence_number).sort).to eq([1, 2])
  end
end
