require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 4 — déclaré face à la banque : ce que l'artisan a noté,
# ce qui est arrivé à son mot-clé, ce qu'il a noté en espèces.
RSpec.describe ConsignmentReport do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:emilie) { Consignor.create!(name: "Émilie", settlement_mode: "invoice", commission_percent: 20) }
  let!(:bruno) { Consignor.create!(name: "Bruno", settlement_mode: "invoice") }
  let(:report) { emilie.consignment_reports.create!(period_month: Date.new(2026, 6, 1), status: "declared") }

  def transfer(consignor, cents, date)
    build_cash_entry(bank, amount_cents: cents, entry_date: date).tap { |e| e.update!(consignor: consignor) }
  end

  before do
    report.consignment_report_lines.create!(label: "Savon", quantity: 4, unit_price_cents: 500, payment_method: "qr")
    report.consignment_report_lines.create!(label: "Bougie", quantity: 1, unit_price_cents: 800, payment_method: "cash")
    report.consignment_report_lines.create!(label: "Baume", quantity: 1, unit_price_cents: 700)
  end

  it "additionne les virements de l'artisan sur le mois du relevé, et seulement les siens" do
    transfer(emilie, 1_200, Date.new(2026, 6, 3))
    transfer(emilie, 800, Date.new(2026, 6, 28))
    transfer(emilie, 999, Date.new(2026, 7, 1))
    transfer(bruno, 5_000, Date.new(2026, 6, 10))
    transfer(emilie, 400, Date.new(2026, 6, 12)).tap { |e| e.update!(status: "excluded", excluded_reason: "doublon") }

    expect(report.received_cents).to eq(2_000)
  end

  it "compte les espèces déclarées depuis les lignes payées en espèces" do
    expect(report.cash_declared_cents).to eq(800)
  end

  it "calcule l'écart : déclaré − reçu − espèces" do
    transfer(emilie, 2_000, Date.new(2026, 6, 3))

    expect(report.displayed_gross_cents).to eq(3_500)
    expect(report.bank_gap_cents).to eq(700)
  end

  it "un écart négatif quand il est entré plus que déclaré" do
    transfer(emilie, 3_000, Date.new(2026, 6, 3))

    expect(report.bank_gap_cents).to eq(-300)
  end
end

RSpec.describe CashEntry do
  include FinanceBuilders

  it "ne rattache un artisan qu'à un encaissement" do
    entity = build_legal_entity
    bank = build_cash_account(entity, build_general_account(code: "550000", name: "Banque"))
    entry = build_cash_entry(bank, amount_cents: -1_000)
    entry.consignor = Consignor.create!(name: "Émilie", settlement_mode: "invoice")

    expect(entry).not_to be_valid
    expect(entry.errors[:consignor].join).to include("encaissement")
  end
end
