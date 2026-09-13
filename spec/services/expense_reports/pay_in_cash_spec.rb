require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #241, phase 1 — « payée en espèces ». Le geste ne note pas « payée » : il
# crée une vraie sortie de caisse, affectée sur le 440000 avec la note en
# document. Sans ça, la dette resterait au grand livre alors que l'argent est
# parti, et la caisse serait fausse de la même somme.
RSpec.describe ExpenseReports::PayInCash do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
  let!(:supplier_account) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:expense_account) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let!(:cash_general) { build_general_account(code: "570000", name: "Caisse", klass: 5, nature: "asset") }
  let!(:cash_account) { build_cash_account(entity, cash_general, name: "Caisse du domaine", kind: "cash") }
  let(:human) { Human.create!(name: "Sébastien Test") }

  let(:report) do
    report = ExpenseReport.create!(human: human, legal_entity: entity, submitted_on: Date.current)
    report.expense_lines.create!(spent_on: Date.current, label: "Visserie", amount_cents: 8_740,
                                 general_account: expense_account)
    ExpenseReports::Process.new(expense_report: report.reload).run!
  end

  it "crée la sortie de caisse, l'affecte au 440000 et passe la note en payée" do
    described_class.new(expense_report: report).run!

    entry = CashEntry.order(:id).last
    expect(entry.cash_account).to eq(cash_account)
    expect(entry.amount_cents).to eq(-8_740)
    expect(entry.status).to eq("allocated")

    allocation = entry.cash_allocations.sole
    expect(allocation.general_account).to eq(supplier_account)
    expect(allocation.document).to eq(report)
    expect(allocation.third_party.human).to eq(human)

    expect(report.reload.status).to eq("paid")
    expect(report.paid_on).to eq(Date.current)
    expect(report.settled_cents).to eq(8_740)
  end

  it "comptabilise la sortie de caisse" do
    described_class.new(expense_report: report).run!

    expect(CashEntry.order(:id).last).to be_posted
  end

  it "refuse une note qui n'est pas en traitement" do
    brouillon = ExpenseReport.create!(human: human, legal_entity: entity)

    expect { described_class.new(expense_report: brouillon).run! }
      .to raise_error(described_class::BadStatus)
  end

  it "refuse quand aucune caisse active n'existe pour l'entité" do
    cash_account.update!(active: false)

    expect { described_class.new(expense_report: report).run! }
      .to raise_error(described_class::NoCashAccount)
  end

  it "refuse d'écrire dans un mois arrêté" do
    report
    MonthClosing.create!(period_month: Date.current.beginning_of_month, closed_at: Time.current)

    expect { described_class.new(expense_report: report).run! }
      .to raise_error(described_class::MonthClosed)
  end
end
