require "rails_helper"
require "rake"

# Issue #354 — `rake finance:audit_member_charges`, l'outil qui rend le
# décalage visible. Lecture seule : aucune de ces specs ne doit voir une
# écriture apparaître.
RSpec.describe "finance:audit_member_charges" do
  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before do
    Rake::Task["finance:audit_member_charges"].reenable
    ENV["YEAR"] = "2026"
    ENV["ACCOUNT"] = nil
  end

  after { %w[YEAR ACCOUNT].each { |key| ENV[key] = nil } }

  let(:household) { Household.create!(name: "Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Michael & Malau") }

  def charge(month, cents)
    account.account_entries.create!(entry_date: Date.new(2026, month, -1), amount_cents: cents,
                                    flow: "charges", kind: "recurring", label: "Charges habitants")
  end

  def settle(month, cents)
    account.account_entries.create!(entry_date: Date.new(2026, month, 5), amount_cents: -cents,
                                    flow: "charges", kind: "settlement", label: "Règlement")
  end

  def run_task = Rake::Task["finance:audit_member_charges"].invoke

  it "tourne sans erreur sur une base vide" do
    expect { run_task }.to output(/0 compte\(s\) avec des charges, 0 décalage\(s\) probable\(s\)/).to_stdout
  end

  it "sort le tableau mois par mois et signale le décalage" do
    charge(1, 30_000)
    (2..9).each { |month| charge(month, 34_500) }
    (2..9).each { |month| settle(month, 34_500) }

    expect { run_task }.to output(
      /2026-01.*300\.00.*0\.00.*300\.00.*300\.00.*écart cumulé constant à 300\.00 € sur 9 mois.*1 décalage\(s\) probable\(s\)/m
    ).to_stdout
  end

  it "ne signale rien sur une dette qui grandit" do
    (1..9).each { |month| charge(month, 30_000) }
    (1..3).each { |month| settle(month, 30_000) }

    expect { run_task }.to output(/0 décalage\(s\) probable\(s\)/).to_stdout
  end

  it "se restreint au compte nommé" do
    charge(1, 30_000)
    autre = MemberAccount.create!(kind: "entity", name: "Semisto")
    autre.account_entries.create!(entry_date: Date.new(2026, 1, 31), amount_cents: 5_000,
                                  flow: "charges", kind: "recurring", label: "Charges")
    ENV["ACCOUNT"] = account.code

    expect { run_task }.to output(/1 compte\(s\) avec des charges/).to_stdout
  end

  it "n'écrit rien" do
    charge(1, 30_000)
    (2..9).each { |month| charge(month, 34_500) }
    (2..9).each { |month| settle(month, 34_500) }

    expect { expect { run_task }.to output(/Lecture seule/).to_stdout }
      .not_to change { [AccountEntry.count, AccountSettlement.count] }
  end
end
