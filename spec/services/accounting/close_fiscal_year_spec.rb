require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La clôture annuelle (revue expert-comptable du 2026-10-20) : affecter le
# résultat, verrouiller, poser l'à-nouveau de l'exercice suivant.
RSpec.describe Accounting::CloseFiscalYear do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:year_2025) { build_fiscal_year(entity, year: 2025) }
  let(:bank) { build_general_account(code: "550000", name: "Banque") }
  let(:suppliers) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }
  let(:rent) { build_general_account(code: "610100", name: "Loyers", klass: 6, nature: "expense") }
  let(:supplier) { ThirdParty.create!(name: "Voo", kind: "supplier") }

  def post(debit, credit, cents, date: Date.new(2025, 6, 1), third_party: nil)
    Accounting::PostDocument.new(
      legal_entity: entity, journal: "misc", entry_date: date, label: "Test",
      lines: [{ account: debit, debit_cents: cents, third_party: third_party },
              { account: credit, credit_cents: cents, third_party: third_party }]
    ).run!
  end

  before do
    post(bank, revenue, 100_000)
    post(rent, suppliers, 30_000, third_party: supplier)
  end

  def balance(code, year)
    JournalLine.joins(:journal_entry, :general_account)
               .where(general_accounts: { code: code }, journal_entries: { fiscal_year_id: year.id })
               .sum("debit_cents - credit_cents")
  end

  it "affecte le bénéfice, verrouille, clôture et pose l'à-nouveau de l'exercice suivant" do
    preview = described_class.new(fiscal_year: year_2025).preview
    expect(preview.result_cents).to eq(70_000)
    expect(preview).to be_closable
    expect(preview.next_year_exists).to be(false)

    described_class.new(fiscal_year: year_2025, whodunnit: "spec").run!

    expect(year_2025.reload).to be_closed
    expect(year_2025.journal_entries.where(locked_at: nil)).to be_empty
    expect(balance("693000", year_2025)).to eq(70_000)
    expect(balance("140000", year_2025)).to eq(-70_000)
    # Charges et produits de l'exercice font zéro une fois le résultat affecté.
    sixes_sevens = JournalLine.joins(:journal_entry, :general_account)
                              .where(general_accounts: { klass: [6, 7] }, journal_entries: { fiscal_year_id: year_2025.id })
    expect(sixes_sevens.sum("debit_cents - credit_cents")).to eq(0)

    year_2026 = entity.fiscal_years.find_by(starts_on: Date.new(2026, 1, 1))
    expect(year_2026).to be_present
    opening = year_2026.journal_entries.find_by(journal: "opening")
    expect(opening.entry_date).to eq(Date.new(2026, 1, 1))
    expect(balance("550000", year_2026)).to eq(100_000)
    expect(balance("140000", year_2026)).to eq(-70_000)
    supplier_line = opening.journal_lines.find { |line| line.general_account.code == "440000" }
    expect(supplier_line).to have_attributes(credit_cents: 30_000, third_party: supplier)
    expect(opening.journal_lines.map { |line| line.general_account.klass }).to all(be <= 5)
  end

  it "affecte une perte au débit du résultat reporté, contre 793" do
    post(rent, bank, 200_000)
    described_class.new(fiscal_year: year_2025).run!

    expect(balance("140000", year_2025)).to eq(130_000)
    expect(balance("793000", year_2025)).to eq(-130_000)
  end

  it "clôture dans l'ordre : refuse tant que l'exercice précédent est ouvert" do
    build_fiscal_year(entity, year: 2024)

    preview = described_class.new(fiscal_year: year_2025).preview
    expect(preview.blockers.join).to include("Clôture d'abord l'exercice 2024")
    expect { described_class.new(fiscal_year: year_2025).run! }.to raise_error(described_class::Refused)
    expect(year_2025.reload).not_to be_closed
  end

  context "quand l'exercice suivant a déjà un à-nouveau" do
    let!(:year_2026) { build_fiscal_year(entity, year: 2026) }

    before do
      entity.fiscal_years.reset
      Accounting::PostDocument.new(
        legal_entity: entity, journal: "opening", entry_date: Date.new(2026, 1, 1), label: "À-nouveau Winbooks",
        lines: [{ account: bank, debit_cents: 5_000 }, { account: build_general_account(code: "100000", name: "Fonds", klass: 1, nature: "equity"), credit_cents: 5_000 }]
      ).run!
    end

    it "refuse de poser un second à-nouveau par défaut" do
      expect(described_class.new(fiscal_year: year_2025).preview.blockers.join).to include("a déjà un à-nouveau")
    end

    it "remplace l'existant en le contre-passant" do
      described_class.new(fiscal_year: year_2025, opening: "replace").run!

      expect(balance("550000", year_2026)).to eq(100_000)
      expect(balance("100000", year_2026)).to eq(0)
    end

    it "garde l'existant et ne pose rien avec « aucun »" do
      described_class.new(fiscal_year: year_2025, opening: "none").run!

      expect(year_2025.reload).to be_closed
      expect(balance("550000", year_2026)).to eq(5_000)
    end
  end

  it "fait partir le grand livre de l'exercice suivant de son à-nouveau, sans recompter l'historique" do
    described_class.new(fiscal_year: year_2025).run!
    year_2026 = entity.fiscal_years.find_by(starts_on: Date.new(2026, 1, 1))
    post(bank, revenue, 1_000, date: Date.new(2026, 3, 1))

    balances = Accounting::Balances.new(entity)
    expect(balances.through(Date.new(2026, 12, 31))[bank.id]).to eq(101_000)
    expect(balances.before(Date.new(2026, 1, 1))[bank.id]).to eq(0)
    expect(balances.before(Date.new(2026, 2, 1))[bank.id]).to eq(100_000)
    # Les produits repartent de zéro : 2026 ne voit que les siens.
    expect(balances.through(Date.new(2026, 12, 31))[revenue.id]).to eq(-1_000)
    expect(year_2026.reload).not_to be_closed
  end

  describe Accounting::ReopenFiscalYear do
    before { Accounting::CloseFiscalYear.new(fiscal_year: year_2025).run! }

    let(:year_2026) { entity.fiscal_years.find_by(starts_on: Date.new(2026, 1, 1)) }

    it "contre-passe l'affectation et l'à-nouveau, déverrouille, puis permet de reclôturer" do
      described_class.new(fiscal_year: year_2025, reason: "Facture oubliée", whodunnit: "spec").run!

      expect(year_2025.reload).not_to be_closed
      expect(year_2025.journal_entries.where.not(locked_at: nil)).to be_empty
      expect(balance("140000", year_2025)).to eq(0)
      expect(balance("550000", year_2026)).to eq(0)

      post(rent, bank, 10_000)
      Accounting::CloseFiscalYear.new(fiscal_year: year_2025).run!
      expect(balance("140000", year_2026)).to eq(-60_000)
      expect(balance("550000", year_2026)).to eq(90_000)
    end

    it "exige un motif" do
      expect(described_class.new(fiscal_year: year_2025, reason: "").refusal).to include("motif")
    end

    it "ne rouvre que le dernier exercice clôturé" do
      Accounting::CloseFiscalYear.new(fiscal_year: year_2026).run!

      expect(described_class.new(fiscal_year: year_2025, reason: "x").refusal).to include("Rouvre d'abord l'exercice 2026")
    end
  end
end
