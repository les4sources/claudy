require "rails_helper"
require "rake"

# Issue #160 — `rake finance:verify_ledger`. Le filet qui doit être vert avant
# toute émission réelle : il recalcule chaque solde depuis les écritures et le
# compare aux décomptes figés.
RSpec.describe "finance:verify_ledger" do
  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before { Rake::Task["finance:verify_ledger"].reenable }

  let(:household) { Household.create!(name: "Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  def add_entry(date, cents)
    account.account_entries.create!(entry_date: date, amount_cents: cents, label: "Ligne")
  end

  def run_task
    Rake::Task["finance:verify_ledger"].invoke
    :ok
  rescue SystemExit
    :exit_1
  end

  it "sort sans écart sur une chaîne cohérente" do
    add_entry(Date.new(2026, 7, 15), 1000)
    add_entry(Date.new(2026, 8, 15), 2000)
    Finance::IssueStatement.new(member_account: account, month: "2026-07").run!
    Finance::IssueStatement.new(member_account: account, month: "2026-08").run!

    expect { expect(run_task).to eq(:ok) }.to output(/Aucun écart/).to_stdout
  end

  # Le contrôle qui compte : une écriture modifiée dans le dos du décompte doit
  # être visible, pas absorbée silencieusement.
  it "sort en échec quand un décompte figé ne colle plus à ses écritures" do
    add_entry(Date.new(2026, 7, 15), 1000)
    statement = Finance::IssueStatement.new(member_account: account, month: "2026-07").run!
    statement.update_column(:closing_balance_cents, 999_999)

    expect { expect(run_task).to eq(:exit_1) }.to output(/écart/).to_stdout
  end

  it "détecte une rupture de chaînage entre deux mois" do
    add_entry(Date.new(2026, 7, 15), 1000)
    add_entry(Date.new(2026, 8, 15), 2000)
    Finance::IssueStatement.new(member_account: account, month: "2026-07").run!
    aout = Finance::IssueStatement.new(member_account: account, month: "2026-08").run!
    aout.update_column(:opening_balance_cents, 42)

    expect { expect(run_task).to eq(:exit_1) }.to output(/ouverture/).to_stdout
  end
end
