require "rails_helper"
require "rake"
require Rails.root.join("spec/support/finance_builders")

# La pension de Balthazar (Michael, 2026-10-19) : 30 € par mois depuis février
# 2022, une règle posée en octobre 2026 qui démarre en mars 2022, un barème qui
# ne remonte qu'à 2023.
RSpec.describe "rattrapage:pension_balthazar", type: :task do
  include FinanceBuilders
  include ActiveSupport::Testing::TimeHelpers

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("rattrapage:pension_balthazar")
  end

  def run_task(apply: false)
    task = Rake::Task["rattrapage:pension_balthazar"]
    task.reenable
    previous_apply = ENV["APPLY"]
    ENV["APPLY"] = apply ? "1" : nil
    original = $stdout
    buffer = StringIO.new
    $stdout = buffer
    task.invoke
    buffer.string
  ensure
    $stdout = original
    ENV["APPLY"] = previous_apply
    Pricing::Rates.reset!
  end

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4) }
  let!(:produit) { build_general_account(code: "702001", name: "Balthazar", klass: 7, nature: "revenue") }
  let!(:triodos) { build_cash_account(entity, banque) }
  let!(:caisse) { build_cash_account(entity, banque, name: "Caisse du domaine", kind: "cash") }
  let!(:compte) do
    household = Household.create!(name: "Béné", kind: "resident", moved_in_on: Date.new(2022, 1, 1))
    MemberAccount.create!(kind: "household", household: household, name: "Béné", code: "SRC-0005")
  end
  let!(:charge) do
    Rates::SeedSourciers.new.run
    RecurringCharge.create!(member_account: compte, label: "Pension pour Balthazar", basis: "flat", flow: "pet",
                            rate_key: "pet.balthazar_monthly", starts_on: Date.new(2022, 3, 1))
  end

  def virement(cents, date, communication, comptabilise:, account: triodos)
    entry = CashEntry.create!(cash_account: account, entry_date: date, amount_cents: cents, label: communication,
                              communication: communication, counterparty_name: "MLLE BENEDICTE GRIGNARD")
    entry.cash_allocations.create!(general_account: produit, amount_cents: cents, legal_entity: entity) if comptabilise
    entry
  end

  let!(:fev_mars) { virement(6_000, Date.new(2022, 3, 16), "Balthazar - fev-mars", comptabilise: true) }
  let!(:avril) { virement(3_000, Date.new(2022, 4, 8), "Frais Balthazar - avril 22", comptabilise: true) }
  let!(:marechal) { virement(3_000, Date.new(2022, 4, 30), "Maréchal Balthazar", comptabilise: true, account: caisse) }
  let!(:octobre) { virement(3_000, Date.new(2026, 10, 5), "Pension Balthazar", comptabilise: false) }

  before { travel_to Date.new(2026, 10, 19) }
  after { travel_back }

  it "montre tout et n'écrit rien sans APPLY" do
    output = nil
    expect { output = run_task }.not_to change(AccountEntry, :count)

    expect(output).to include("début avancé du  1 mars 2022 au  1 février 2022")
    expect(output).to include("en vigueur depuis le  1 février 2022")
    expect(output).to include("Rien n'a été écrit")
    expect(charge.reload.starts_on).to eq(Date.new(2022, 3, 1))
  end

  it "écrit avec APPLY=1, sans doublon au second passage" do
    run_task(apply: true)

    expect(charge.reload.starts_on).to eq(Date.new(2022, 2, 1))
    expect(compte.account_entries.where(flow: "pet", kind: "recurring").count).to eq(57)
    expect(compte.account_settlements.pluck(:reference))
      .to include("reprise-pet:2022-02", "reprise-pet:2022-03", "reprise-pet:2022-04")
    expect(octobre.reload.cash_allocations.sole.general_account).to eq(clients)
    expect(marechal.reload.cash_allocations.sole.general_account).to eq(produit)

    expect { run_task(apply: true) }.not_to change(AccountEntry, :count)
  end
end
