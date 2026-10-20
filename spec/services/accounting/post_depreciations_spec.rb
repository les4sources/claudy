require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le registre des immobilisations et ses dotations (revue expert-comptable du
# 2026-10-20) : linéaire, prorata temporis au mois.
RSpec.describe Accounting::PostDepreciations do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:year_2025) { build_fiscal_year(entity, year: 2025) }
  let(:furniture) { build_general_account(code: "240000", name: "Mobilier", klass: 2) }
  let(:depreciation) { build_general_account(code: "240001", name: "Amortissements mobilier", klass: 2) }
  let(:dotation) { build_general_account(code: "630100", name: "Dotations", klass: 6, nature: "expense") }

  def asset(**attributes)
    FixedAsset.create!({ legal_entity: entity, name: "Poêle", general_account: furniture, depreciation_account: depreciation,
                         expense_account: dotation, acquired_on: Date.new(2025, 9, 15), acquisition_cents: 120_000,
                         useful_life_years: 5 }.merge(attributes))
  end

  it "dote au prorata des mois la première année, puis une annuité" do
    poele = asset
    expect(poele.depreciation_due_cents(year_2025)).to eq(8_000) # 4 mois sur 60

    described_class.new(fiscal_year: year_2025).run!
    entry = poele.reload.depreciations.first.journal_entry
    expect(entry.journal_lines.map { |l| [l.general_account.code, l.debit_cents, l.credit_cents] })
      .to contain_exactly(["630100", 8_000, 0], ["240001", 0, 8_000])
    expect(entry.entry_date).to eq(Date.new(2025, 12, 31))

    year_2026 = build_fiscal_year(entity, year: 2026)
    expect(poele.reload.depreciation_due_cents(year_2026)).to eq(24_000)
    expect(poele.net_book_value_cents).to eq(112_000)
  end

  it "ne dote pas deux fois le même exercice" do
    asset
    described_class.new(fiscal_year: year_2025).run!

    expect { described_class.new(fiscal_year: year_2025).run! }.to raise_error(described_class::Refused, /Aucune dotation/)
  end

  it "part des amortissements déjà actés avant Claudy" do
    ancien = asset(acquired_on: Date.new(2021, 1, 1), prior_depreciation_cents: 96_000)
    expect(ancien.depreciation_due_cents(year_2025)).to eq(24_000)
    expect(asset(name: "Fini", acquired_on: Date.new(2019, 1, 1), prior_depreciation_cents: 120_000)
             .depreciation_due_cents(year_2025)).to eq(0)
  end

  it "annule une dotation d'un exercice ouvert pour la refaire" do
    poele = asset
    described_class.new(fiscal_year: year_2025).run!
    Accounting::CancelDepreciation.new(depreciation: poele.depreciations.first).run!

    expect(poele.reload.depreciations).to be_empty
    lignes = JournalLine.joins(:general_account).where(general_accounts: { code: "240001" })
    expect(lignes.sum("debit_cents - credit_cents")).to eq(0)
    expect(described_class.new(fiscal_year: year_2025).rows.map(&:amount_cents)).to eq([8_000])
  end

  it "signale à la clôture les dotations pas encore passées" do
    asset
    preview = Accounting::CloseFiscalYear.new(fiscal_year: year_2025).preview

    expect(preview.warnings.join).to include("Dotations aux amortissements non passées pour 1 immobilisation")
  end
end
