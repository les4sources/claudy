require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Ce que ces exemples protègent, c'est la reprise Winbooks : 1 400 documents
# rejouables sans jamais se doubler, et un refus net quand la source dit
# quelque chose que le référentiel ne connaît pas.
RSpec.describe Accounting::ImportLedgerDocument do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2024) }
  let!(:supplier_account) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:expense) { build_general_account(code: "612003", name: "Gaz", klass: 6, nature: "expense") }
  let!(:antargaz) { ThirdParty.create!(code: "ANTARGAZ", name: "Antargaz", kind: "supplier") }

  before { described_class.reset_cache! }

  def import(external_ref: "winbooks:2024:ACHATS:4", lines: nil)
    described_class.new(
      legal_entity: entity,
      source_system: "winbooks",
      external_ref: external_ref,
      journal: "purchases",
      entry_date: Date.new(2024, 1, 12),
      label: "Antargaz — location citerne",
      lines: lines || [
        { account_code: "612003", debit_cents: 12_100, label: "Location citerne" },
        { account_code: "440000", credit_cents: 12_100, third_party_code: "ANTARGAZ" }
      ],
      payload: { docnr: "4" }
    ).run!
  end

  it "produit une écriture équilibrée rattachée à sa pièce d'origine" do
    entry = import

    expect(entry.debit_cents).to eq(12_100)
    expect(entry.credit_cents).to eq(12_100)
    expect(entry.journal).to eq("purchases")
    expect(entry.source).to be_a(LedgerDocument)
    expect(entry.source.external_ref).to eq("winbooks:2024:ACHATS:4")
    expect(entry.source.payload).to eq("docnr" => "4")
  end

  it "porte le tiers sur la ligne de dette, pas sur la charge" do
    entry = import

    dette = entry.journal_lines.find { |line| line.general_account.code == "440000" }
    charge = entry.journal_lines.find { |line| line.general_account.code == "612003" }

    expect(dette.third_party).to eq(antargaz)
    expect(charge.third_party).to be_nil
  end

  # Sans ça, relancer la reprise après une interruption doublerait chaque euro
  # déjà repris — c'est le risque numéro un de tout l'exercice.
  it "rejoué à l'identique, ne crée pas une seconde écriture" do
    first = import
    second = import

    expect(second.id).to eq(first.id)
    expect(JournalEntry.count).to eq(1)
    expect(LedgerDocument.count).to eq(1)
  end

  it "distingue deux documents que seul leur numéro sépare" do
    import(external_ref: "winbooks:2024:ACHATS:4")
    import(external_ref: "winbooks:2024:ACHATS:5")

    expect(JournalEntry.count).to eq(2)
  end

  it "refuse un document déséquilibré sans rien écrire" do
    expect {
      import(lines: [
        { account_code: "612003", debit_cents: 12_100 },
        { account_code: "440000", credit_cents: 12_000, third_party_code: "ANTARGAZ" }
      ])
    }.to raise_error(described_class::UnbalancedDocument, /écart de 100 centimes/)

    expect(JournalEntry.count).to eq(0)
    expect(LedgerDocument.count).to eq(0)
  end

  it "refuse un compte absent du plan comptable plutôt que de le créer" do
    expect {
      import(lines: [
        { account_code: "699999", debit_cents: 100 },
        { account_code: "440000", credit_cents: 100, third_party_code: "ANTARGAZ" }
      ])
    }.to raise_error(described_class::UnknownAccount, /699999/)

    expect(GeneralAccount.find_by(code: "699999")).to be_nil
  end

  it "refuse un tiers inconnu plutôt que de l'inventer" do
    expect {
      import(lines: [
        { account_code: "612003", debit_cents: 100 },
        { account_code: "440000", credit_cents: 100, third_party_code: "FANTOME" }
      ])
    }.to raise_error(described_class::UnknownThirdParty, /FANTOME/)

    expect(ThirdParty.find_by(code: "FANTOME")).to be_nil
  end
end
