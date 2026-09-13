require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #241, phase 1 — le retour en arrière. L'écriture n'est pas supprimée,
# elle est contre-passée ; le numéro de pièce, lui, reste sur la note. Un numéro
# attribué ne se réattribue pas, et l'abandonner ouvrirait un trou dans la
# séquence que le contrôle signalerait à juste titre.
RSpec.describe ExpenseReports::Unprocess do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
  let!(:supplier_account) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:expense_account) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let(:human) { Human.create!(name: "Sébastien Test") }

  let(:report) do
    report = ExpenseReport.create!(human: human, legal_entity: entity, submitted_on: Date.current)
    report.expense_lines.create!(spent_on: Date.current, label: "Visserie", amount_cents: 8_740,
                                 general_account: expense_account)
    ExpenseReports::Process.new(expense_report: report.reload).run!
  end

  it "contre-passe l'écriture et rouvre la note en gardant son numéro" do
    reference = report.reference
    originale = report.journal_entry

    described_class.new(expense_report: report).run!

    report.reload
    expect(report.status).to eq("recorded")
    expect(report.posted_at).to be_nil
    expect(report.reference).to eq(reference)
    expect(report.sequence_number).to eq(1)
    expect(JournalEntry.exists?(reversal_of_id: originale.id)).to be(true)
  end

  it "permet de corriger puis de repasser la note — sur une NOUVELLE écriture" do
    described_class.new(expense_report: report).run!

    report.reload.expense_lines.first.update!(amount_cents: 9_000)
    ExpenseReports::Process.new(expense_report: report.reload).run!

    report.reload
    expect(report.status).to eq("processing")
    expect(report.reference).to eq("NF-#{Date.current.year}-001")
    expect(report.journal_entry.journal_lines.sum(&:debit_cents)).to eq(9_000)
  end

  it "refuse de rouvrir une note payée" do
    report.update_columns(status: "paid")

    expect { described_class.new(expense_report: report.reload).run! }
      .to raise_error(described_class::AlreadyPaid)
  end

  it "refuse de rouvrir une note qui n'est pas en traitement" do
    brouillon = ExpenseReport.create!(human: human, legal_entity: entity)

    expect { described_class.new(expense_report: brouillon).run! }
      .to raise_error(described_class::NotProcessing)
  end
end
