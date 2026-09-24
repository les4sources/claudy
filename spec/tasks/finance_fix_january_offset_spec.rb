require "rails_helper"
require "rake"

# Issue #354 — `rake finance:fix_january_offset`, la correction du décalage
# hérité de la reprise comptable. Dates figées : la tâche reçoit son année.
RSpec.describe "finance:fix_january_offset" do
  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before do
    Rake::Task["finance:fix_january_offset"].reenable
    ENV["YEAR"] = "2026"
    ENV["ACCOUNTS"] = nil
    ENV["APPLY"] = nil
  end

  after { %w[YEAR ACCOUNTS APPLY].each { |key| ENV[key] = nil } }

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

  # Le décalage de Michael & Malau : janvier jamais réglé, les huit mois
  # suivants réglés au centime.
  def build_offset(january_cents: 30_000, monthly_cents: 34_500)
    charge(1, january_cents)
    (2..9).each { |month| charge(month, monthly_cents) }
    (2..9).each { |month| settle(month, monthly_cents) }
  end

  def run_task
    Rake::Task["finance:fix_january_offset"].invoke
  end

  it "n'écrit rien en dry-run" do
    build_offset
    ENV["ACCOUNTS"] = account.code

    expect { run_task }.to output(/1 correction\(s\) à écrire.*Rien n'a été écrit/m).to_stdout
    expect(AccountSettlement.count).to eq(0)
  end

  it "écrit un seul règlement, daté du 31 décembre, du montant exact de janvier" do
    build_offset
    ENV["ACCOUNTS"] = account.code
    ENV["APPLY"] = "1"

    expect { run_task }.to output(/1 correction\(s\) à écrire/).to_stdout

    settlement = AccountSettlement.sole
    expect(settlement.member_account).to eq(account)
    expect(settlement.amount_cents).to eq(30_000)
    expect(settlement.received_on).to eq(Date.new(2025, 12, 31))
    expect(settlement.reference).to eq("reprise-offset:#{account.code}:2026-01")
    expect(settlement.notes).to include("reprise comptable", "#354")

    entry = settlement.account_entries.sole
    expect(entry.amount_cents).to eq(-30_000)
    expect(entry.entry_date).to eq(Date.new(2025, 12, 31))
    expect(entry.flow).to eq("charges")
    expect(entry.kind).to eq("settlement")
  end

  # La correction doit refermer le trou pour de bon : le lettrage FIFO impute
  # un règlement antérieur sur la charge de janvier dès qu'elle se présente.
  it "solde la charge de janvier une fois appliquée" do
    build_offset
    ENV["ACCOUNTS"] = account.code
    ENV["APPLY"] = "1"

    expect { run_task }.to output(/correction/).to_stdout

    expect(account.reload.balance_cents).to eq(0)
    expect(MemberAccounts::Outstanding.new(account.reload)).not_to be_any
    expect(Finance::MemberChargesAudit.new(year: 2026, codes: account.code).run!.first).not_to be_offset
  end

  it "ne crée rien la seconde fois" do
    build_offset
    ENV["ACCOUNTS"] = account.code
    ENV["APPLY"] = "1"

    expect { run_task }.to output(/correction/).to_stdout
    Rake::Task["finance:fix_january_offset"].reenable

    expect { run_task }.to output(/déjà corrigé/).to_stdout
    expect(AccountSettlement.count).to eq(1)
    expect(AccountEntry.where.not(account_settlement_id: nil).count).to eq(1)
  end

  it "refuse un compte sans charge de janvier" do
    (2..9).each { |month| charge(month, 34_500) }
    ENV["ACCOUNTS"] = account.code
    ENV["APPLY"] = "1"

    expect { run_task }.to output(/refusé — aucune charge de janvier/).to_stdout
    expect(AccountSettlement.count).to eq(0)
  end

  it "refuse un compte dont janvier porte deux charges" do
    charge(1, 20_000)
    charge(1, 10_000)
    (2..9).each { |month| charge(month, 34_500) }
    (2..9).each { |month| settle(month, 34_500) }
    ENV["ACCOUNTS"] = account.code
    ENV["APPLY"] = "1"

    expect { run_task }.to output(/refusé — 2 charges en janvier/).to_stdout
    expect(AccountSettlement.count).to eq(0)
  end

  it "refuse un compte qui n'a pas le symptôme" do
    (1..9).each { |month| charge(month, 30_000) }
    (1..9).each { |month| settle(month, 30_000) }
    ENV["ACCOUNTS"] = account.code
    ENV["APPLY"] = "1"

    expect { run_task }.to output(/refusé — aucun palier.*n'a pas le symptôme/).to_stdout
    expect(AccountSettlement.count).to eq(0)
  end

  # Le cas qui a failli écrire 300 € de créance imaginaire (dry-run du
  # 2026-09-23) : janvier soldé, un trop-perçu de 45 € en février, et le mois
  # courant qui attend son virement. Le cumul de fin d'année valait alors la
  # charge mensuelle entière — assez pour tromper l'ancienne garde.
  it "refuse un compte à jour dont seul le mois courant n'est pas encore réglé" do
    charge(1, 30_000)
    settle(1, 30_000)
    (2..9).each { |month| charge(month, 34_500) }
    settle(2, 39_000)
    (3..8).each { |month| settle(month, 34_500) }
    ENV["ACCOUNTS"] = account.code
    ENV["APPLY"] = "1"

    expect { run_task }.to output(/refusé — palier d'écart de .*inférieur à la charge de janvier/).to_stdout
    expect(AccountSettlement.count).to eq(0)
  end

  it "refuse un code inconnu" do
    ENV["ACCOUNTS"] = "SRC-9999"
    ENV["APPLY"] = "1"

    expect { run_task }.to output(/SRC-9999.*refusé — compte introuvable/).to_stdout
    expect(AccountSettlement.count).to eq(0)
  end

  it "ne fait rien sans compte nommé" do
    build_offset

    expect { run_task }.to output(/Aucun compte nommé/).to_stdout
    expect(AccountSettlement.count).to eq(0)
  end
end
