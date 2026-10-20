require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Une écriture passée ne disparaît jamais, elle se contre-passe. C'est la seule
# façon de garder une numérotation sans trou tout en corrigeant une erreur.
RSpec.describe Accounting::ReverseEntry do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank) { build_general_account(code: "550000", name: "Banque") }
  let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }
  let(:entry) { post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue, amount_cents: 25_000) }

  it "produit une écriture miroir qui annule la première" do
    mirror = described_class.new(journal_entry: entry, entry_date: Date.new(2026, 7, 1)).run!

    expect(mirror.reversal_of).to eq(entry)
    expect(mirror.debit_cents).to eq(25_000)
    expect(mirror.credit_cents).to eq(25_000)

    debit_line = mirror.journal_lines.find { |l| l.debit_cents.positive? }
    expect(debit_line.general_account).to eq(revenue)
  end

  it "laisse le solde du compte à zéro" do
    described_class.new(journal_entry: entry, entry_date: Date.new(2026, 7, 1)).run!

    lignes = JournalLine.joins(:journal_entry).where(general_account_id: bank.id)
    expect(lignes.sum(:debit_cents) - lignes.sum(:credit_cents)).to eq(0)
  end

  # Le solde d'un fournisseur se lit par tiers sur le 440000 : un miroir sans
  # tiers solderait le compte au global en laissant la dette ouverte chez lui.
  it "garde le tiers de chaque ligne" do
    fournisseur = ThirdParty.create!(name: "Brasserie de test", kind: "supplier")
    dettes = build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability")
    paiement = Accounting::PostDocument.new(
      legal_entity: entity, journal: "bank", entry_date: Date.new(2026, 6, 15), label: "Paiement",
      lines: [
        { account: dettes, debit_cents: 8_000, third_party: fournisseur },
        { account: bank, credit_cents: 8_000 }
      ]
    ).run!

    mirror = described_class.new(journal_entry: paiement, entry_date: Date.new(2026, 7, 1)).run!

    ligne = mirror.journal_lines.find { |l| l.general_account == dettes }
    expect(ligne.third_party).to eq(fournisseur)
    expect(ligne.credit_cents).to eq(8_000)
  end

  it "refuse de contre-passer deux fois" do
    described_class.new(journal_entry: entry).run!

    expect {
      described_class.new(journal_entry: entry).run!
    }.to raise_error(described_class::AlreadyReversed)
  end
end
