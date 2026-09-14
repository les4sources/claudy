require "rails_helper"
require "rake"
require Rails.root.join("spec/support/finance_builders")

# Epic #241, phase 1 — le filet. Une note passée en traitement sans écriture, ou
# un trou dans la séquence des pièces, ne se voit pas à l'œil nu trois mois plus
# tard : cette tâche est ce qui regarde à notre place.
RSpec.describe "accounting:verify_expense_reports" do
  include FinanceBuilders

  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before { Rake::Task["accounting:verify_expense_reports"].reenable }

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
  let!(:supplier) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:charge) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }
  let(:human) { Human.create!(name: "Sébastien Test") }

  def run_task
    original = $stdout
    $stdout = StringIO.new
    Rake::Task["accounting:verify_expense_reports"].invoke
    :ok
  rescue SystemExit
    :exit_1
  ensure
    $stdout = original
  end

  def build_report(amount_cents: 8_740)
    report = ExpenseReport.create!(human: human, legal_entity: entity, submitted_on: Date.current)
    report.expense_lines.create!(spent_on: Date.current, label: "Visserie",
                                 amount_cents: amount_cents, general_account: charge)
    report.reload
  end

  it "sort vide quand tout est cohérent" do
    ExpenseReports::Process.new(expense_report: build_report).run!

    expect(run_task).to eq(:ok)
  end

  it "sort vide quand il n'y a aucune note" do
    expect(run_task).to eq(:ok)
  end

  it "crie quand une note en traitement n'a pas d'écriture" do
    build_report.update_columns(status: "processing", reference: "NF-2026-001")

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand une note en traitement n'a pas de numéro de pièce" do
    report = build_report
    ExpenseReports::Process.new(expense_report: report).run!
    report.update_columns(reference: nil)

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand une note payée n'est pas couverte par ses affectations" do
    report = build_report
    ExpenseReports::Process.new(expense_report: report).run!
    report.update_columns(status: "paid", paid_on: Date.current)

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand la séquence a un trou" do
    premiere = build_report
    seconde = build_report
    ExpenseReports::Process.new(expense_report: premiere).run!
    ExpenseReports::Process.new(expense_report: seconde).run!
    premiere.reload.update_columns(sequence_number: nil, reference: nil, status: "recorded")
    JournalEntry.where(source: premiere).update_all(source_type: nil, source_id: nil)

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand une note encore enregistrée porte déjà une écriture" do
    report = build_report
    ExpenseReports::Process.new(expense_report: report).run!
    report.update_columns(status: "recorded")

    expect(run_task).to eq(:exit_1)
  end
end
