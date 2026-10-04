require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 5 — saisir puis valider le contrôle d'un carnet : la
# validation est le seul geste qui fige la banque et l'écart.
RSpec.describe Shop::RecordMonthlyCheck do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:cellier) { build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue") }
  let(:user) { User.create!(email: "malo@les4sources.be", password: "password123") }
  let(:june) { Date.new(2026, 6, 1) }
  let(:totals) { { sheets_total_cents: 10_000, transfer_total_cents: 7_000, cash_total_cents: 3_000, sheet_numbers: "12, 13" } }

  before do
    entry = build_cash_entry(bank, amount_cents: 6_500, entry_date: Date.new(2026, 6, 8))
    allocate(entry, account: cellier, amount_cents: 6_500, entity: entity)
  end

  def record(validate: false, attributes: totals)
    described_class.new(channel: "grocery", month: june, attributes: attributes, validate: validate, user: user).run!
  end

  it "enregistre un brouillon sans rien figer, et le reprend au même endroit" do
    record(attributes: totals.merge(sheets_total_cents: 4_000))
    check = record

    expect(ShopMonthlyCheck.count).to eq(1)
    expect(check).to be_draft
    expect(check.sheets_total_cents).to eq(10_000)
    expect(check.bank_received_cents).to be_nil
    expect(check.gap_cents).to be_nil
  end

  it "valide en figeant la banque, l'écart et qui a validé" do
    check = record(validate: true)

    expect(check).to be_validated
    expect(check.bank_received_cents).to eq(6_500)
    expect(check.gap_cents).to eq(500)
    expect(check.validated_by).to eq(user)
    expect(check.validated_at).to be_present
    expect(check.versions).to be_present
  end

  it "refuse de toucher un contrôle déjà validé" do
    record(validate: true)

    expect { record(attributes: totals.merge(cash_total_cents: 0)) }
      .to raise_error(described_class::AlreadyValidated)
    expect(ShopMonthlyCheck.sole.cash_total_cents).to eq(3_000)
  end
end
