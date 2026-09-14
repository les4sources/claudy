require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #246, phase 2 — le virement qui solde le compte d'un cuisinier.
RSpec.describe Finance::RecordMemberPayout do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:dettes) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }
  let!(:zoe) { Human.create!(name: "Zoé", email: "zoe@les4sources.be", iban: "BE68539007547034") }
  let!(:compte) { MemberAccount.for_human!(zoe) }

  # 5 portions × 3,50 € en faveur de Zoé.
  before do
    compte.account_entries.create!(entry_date: Date.new(2026, 6, 12), kind: "cook_fee", flow: "meal",
                                   label: "Batch cooking du 12/06", amount_cents: -1_750)
  end

  def ligne_sortante(cents, date: Date.new(2026, 6, 20), iban: nil)
    entry = build_cash_entry(compte_bancaire, amount_cents: -cents, entry_date: date,
                             label: "Virement Zoé")
    entry.update!(counterparty_iban: iban) if iban
    entry
  end

  it "solde le compte et affecte la ligne bancaire" do
    entry = ligne_sortante(1_750)

    described_class.new(member_account: compte, cash_entry: entry).run!

    expect(compte.reload.balance_cents).to eq(0)
    allocation = entry.reload.cash_allocations.first
    expect(allocation.general_account).to eq(dettes)
    expect(allocation.amount_cents).to eq(-1_750)
    expect(allocation.document).to eq(compte)
    expect(allocation.third_party.human).to eq(zoe)
  end

  it "comptabilise la ligne une fois entièrement affectée" do
    entry = ligne_sortante(1_750)

    described_class.new(member_account: compte, cash_entry: entry).run!

    expect(entry.reload.status).to eq("allocated")
    expect(entry.journal_entry).to be_present
  end

  it "écrit une entrée « Virement » datée de la ligne" do
    entry = ligne_sortante(1_750)

    described_class.new(member_account: compte, cash_entry: entry).run!

    virement = compte.account_entries.order(:id).last
    expect(virement.kind).to eq("payout")
    expect(virement.flow).to eq("other")
    expect(virement.amount_cents).to eq(1_750)
    expect(virement.label).to include("20 juin")
  end

  it "accepte un virement partiel sans rendre le compte débiteur" do
    entry = ligne_sortante(1_000)

    described_class.new(member_account: compte, cash_entry: entry, amount_cents: 1_000).run!

    expect(compte.reload.balance_cents).to eq(-750)
  end

  it "refuse de virer plus que le solde dû" do
    entry = ligne_sortante(5_000)

    expect { described_class.new(member_account: compte, cash_entry: entry, amount_cents: 5_000).run! }
      .to raise_error(described_class::TooMuch, /n'attend que/)
  end

  it "refuse un compte qui ne doit rien" do
    entry = ligne_sortante(1_750)
    compte.account_entries.destroy_all

    expect { described_class.new(member_account: compte.reload, cash_entry: entry).run! }
      .to raise_error(described_class::NotCreditor)
  end

  it "refuse une ligne entrante" do
    entry = build_cash_entry(compte_bancaire, amount_cents: 1_750)

    expect { described_class.new(member_account: compte, cash_entry: entry).run! }
      .to raise_error(described_class::WrongDirection)
  end

  it "ne double pas un virement rejoué sur la même ligne" do
    entry = ligne_sortante(1_750)
    described_class.new(member_account: compte, cash_entry: entry).run!

    expect { described_class.new(member_account: compte.reload, cash_entry: entry.reload).run! }
      .to raise_error(StandardError)

    expect(compte.reload.account_entries.where(kind: "payout").count).to eq(1)
  end
end
