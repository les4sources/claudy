require "rails_helper"
require "rake"
require Rails.root.join("spec/support/revenue_share_builders")
require Rails.root.join("spec/support/finance_builders")

# Issue #247 — le filet du lot. Une nuitée reversée deux fois, ou un relevé émis
# sans écriture, ne se voit pas à l'œil nu trois mois plus tard : cette tâche
# est ce qui regarde à notre place.
RSpec.describe "accounting:verify_revenue_shares" do
  include RevenueShareBuilders
  include FinanceBuilders

  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before { Rake::Task["accounting:verify_revenue_shares"].reenable }

  let(:lodging) { build_tiny_house }
  let(:agreement) { build_agreement(lodging) }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:charge) do
    build_general_account(code: GeneralAccount::REVENUE_SHARE_CODE, name: "Reversements",
                          klass: 6, nature: "expense")
  end
  let!(:supplier) do
    build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability")
  end

  def run_task
    original = $stdout
    $stdout = StringIO.new
    Rake::Task["accounting:verify_revenue_shares"].invoke
    :ok
  rescue SystemExit
    :exit_1
  ensure
    $stdout = original
  end

  it "sort vide quand tout est cohérent" do
    build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 50_000)
    statement = RevenueShares::Generate.new(agreement: agreement, period_from: Date.new(2026, 1, 1)).run!
    RevenueShares::Issue.new(statement: statement).run!

    expect(run_task).to eq(:ok)
  end

  it "crie quand un relevé est émis sans écriture" do
    build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 50_000)
    statement = RevenueShares::Generate.new(agreement: agreement, period_from: Date.new(2026, 1, 1)).run!
    statement.update!(status: "issued", issued_at: Time.current)

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand la part ne suit pas la base" do
    build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 50_000)
    statement = RevenueShares::Generate.new(agreement: agreement, period_from: Date.new(2026, 1, 1)).run!
    RevenueShares::Issue.new(statement: statement).run!
    statement.update_column(:share_cents, 99_999)

    expect(run_task).to eq(:exit_1)
  end

  it "refuse en base qu'une nuitée soit relevée deux fois" do
    reservation = build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 50_000)
    premier = RevenueShares::Generate.new(agreement: agreement, period_from: Date.new(2026, 1, 1)).run!
    RevenueShares::Issue.new(statement: premier).run!

    doublon = RevenueShareStatement.create!(revenue_share_agreement: agreement,
                                            period_from: Date.new(2026, 4, 1),
                                            period_to: Date.new(2026, 6, 30))
    # L'index unique partiel est la vraie garde : le doublon n'arrive même pas
    # jusqu'au rake. Celui-ci reste la seconde ligne, pour un doublon entré par
    # un autre chemin (import, migration) — mais la première ligne tient.
    expect {
      doublon.revenue_share_statement_lines.create!(booking: reservation, kind: "booking",
                                                    amount_cents: 50_000)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
