require "rails_helper"
require "rake"
require Rails.root.join("spec/support/finance_builders")

# Epic #243, phase 3 — le filet du comptage. Un écart lissé ne se voit pas à
# l'œil nu six mois plus tard : cette tâche est ce qui regarde à notre place.
RSpec.describe "accounting:verify_cash_counts" do
  include FinanceBuilders
  include ActiveSupport::Testing::TimeHelpers

  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before { Rake::Task["accounting:verify_cash_counts"].reenable }

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:caisse_compte) { build_general_account(code: "570000", name: "Caisse") }
  let(:recettes) { build_general_account(code: "700300", name: "Bar", klass: 7, nature: "revenue") }
  let!(:ecarts) do
    build_general_account(code: GeneralAccount::CASH_DIFFERENCE_CODE, name: "Écarts de caisse",
                          klass: 6, nature: "expense")
  end
  let!(:caisse) { build_cash_account(entity, caisse_compte, name: "Caisse du domaine", kind: "cash") }
  let!(:motif_bar) do
    CashMotif.create!(label: "Bar", direction: "in", general_account: recettes,
                      legal_entity: entity, position: 1)
  end

  def run_task
    original = $stdout
    $stdout = StringIO.new
    Rake::Task["accounting:verify_cash_counts"].invoke
    :ok
  rescue SystemExit
    :exit_1
  ensure
    $stdout = original
  end

  def encaisse(cents)
    Finance::RecordCashLine.new(cash_account: caisse, motif: motif_bar, entry_date: Date.current,
                                label: "Recette du bar", amount_cents: cents).run!
  end

  it "sort vide quand il n'y a rien à compter" do
    expect(run_task).to eq(:ok)
  end

  it "sort vide sur un comptage juste" do
    encaisse(5_000)
    Finance::RecordCashCount.new(cash_account: caisse, counted_on: Date.current,
                                 denominations: { "50.00" => 1 }).run!

    expect(run_task).to eq(:ok)
  end

  it "sort vide sur un écart assumé et écrit" do
    encaisse(5_000)
    Finance::RecordCashCount.new(cash_account: caisse, counted_on: Date.current,
                                 denominations: { "20.00" => 1 }, comment: "Introuvable.",
                                 resolution: "unexplained").run!

    expect(run_task).to eq(:ok)
  end

  it "crie quand un écart inexpliqué n'a pas d'écriture d'ajustement" do
    encaisse(5_000)
    count = Finance::RecordCashCount.new(cash_account: caisse, counted_on: Date.current,
                                         denominations: { "20.00" => 1 }, comment: "Introuvable.",
                                         resolution: "unexplained").run!
    count.update_column(:adjustment_cash_entry_id, nil)

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand un écart validé a perdu son commentaire" do
    encaisse(5_000)
    count = Finance::RecordCashCount.new(cash_account: caisse, counted_on: Date.current,
                                         denominations: { "20.00" => 1 }, comment: "Introuvable.",
                                         resolution: "unexplained").run!
    count.update_column(:comment, nil)

    expect(run_task).to eq(:exit_1)
  end

  # Décision 3 : `expected_cents` est figé. PaperTrail est la seule trace qui
  # permette de le vérifier après coup.
  it "crie quand le solde théorique a été réécrit après validation" do
    encaisse(5_000)
    count = Finance::RecordCashCount.new(cash_account: caisse, counted_on: Date.current,
                                         denominations: { "50.00" => 1 }).run!
    # On force la réécriture en contournant la validation d'immuabilité : c'est
    # exactement ce qu'un script de reprise ou une console ferait, et c'est ce
    # que le rake doit rattraper.
    travel_to(count.validated_at + 1.minute) do
      count.expected_cents = 9_999
      count.save!(validate: false)
    end

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand l'ajustement ne porte pas le montant de l'écart" do
    encaisse(5_000)
    count = Finance::RecordCashCount.new(cash_account: caisse, counted_on: Date.current,
                                         denominations: { "20.00" => 1 }, comment: "Introuvable.",
                                         resolution: "unexplained").run!
    count.update_column(:difference_cents, -1_000)

    expect(run_task).to eq(:exit_1)
  end
end
