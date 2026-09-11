require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #246, phase 2 — les propositions de virement sur « À affecter ».
RSpec.describe Finance::MatchMemberPayouts do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }
  let!(:zoe) { Human.create!(name: "Zoé", iban: "BE68539007547034") }
  let!(:marc) { Human.create!(name: "Marc", iban: "BE62510007547061") }
  let!(:compte_zoe) { MemberAccount.for_human!(zoe) }
  let!(:compte_marc) { MemberAccount.for_human!(marc) }

  before do
    compte_zoe.account_entries.create!(entry_date: Date.new(2026, 6, 12), kind: "cook_fee", flow: "meal",
                                       label: "Batch cooking", amount_cents: -1_750)
    compte_marc.account_entries.create!(entry_date: Date.new(2026, 6, 12), kind: "cook_fee", flow: "meal",
                                        label: "Batch cooking", amount_cents: -3_000)
  end

  def sortante(cents, iban: nil)
    entry = build_cash_entry(compte_bancaire, amount_cents: -cents, label: "Virement")
    entry.update!(counterparty_iban: iban) if iban
    entry
  end

  it "propose le compte dont le montant correspond exactement" do
    matches = described_class.new.for_entry(sortante(1_750))

    expect(matches.map(&:member_account)).to eq([compte_zoe])
    expect(matches.first.reason).to include("exactement ce montant")
  end

  # L'IBAN désigne un compte ; le montant n'est qu'une coïncidence possible.
  it "préfère l'IBAN au montant" do
    matches = described_class.new.for_entry(sortante(1_750, iban: "BE62 5100 0754 7061"))

    expect(matches.first.member_account).to eq(compte_marc)
    expect(matches.first.confidence).to be > matches.last.confidence
  end

  it "ne propose rien sur une ligne entrante" do
    entry = build_cash_entry(compte_bancaire, amount_cents: 1_750)

    expect(described_class.new.for_entry(entry)).to be_empty
  end

  it "ne propose rien sur une ligne déjà affectée" do
    entry = sortante(1_750)
    entry.cash_allocations.create!(general_account: banque, legal_entity: entity, amount_cents: -1_750)

    expect(described_class.new.for_entry(entry.reload)).to be_empty
  end

  it "ignore un compte qui ne doit rien" do
    compte_zoe.account_entries.destroy_all

    expect(described_class.new.for_entry(sortante(1_750))).to be_empty
  end
end

RSpec.describe Finance::MemberPayables do
  let!(:zoe) { Human.create!(name: "Zoé", iban: "BE68539007547034") }
  let!(:sans_iban) { Human.create!(name: "Lino") }
  let!(:compte_zoe) { MemberAccount.for_human!(zoe) }
  let!(:compte_lino) { MemberAccount.for_human!(sans_iban) }

  before do
    compte_zoe.account_entries.create!(entry_date: Date.current, kind: "cook_fee", flow: "meal",
                                       label: "Batch cooking", amount_cents: -1_750)
    compte_lino.account_entries.create!(entry_date: Date.current, kind: "cook_fee", flow: "meal",
                                        label: "Batch cooking", amount_cents: -700)
  end

  it "additionne ce que la maison doit" do
    expect(described_class.new.total_cents).to eq(2_450)
  end

  # Masquer un compte sans IBAN reviendrait à faire disparaître la dette parce
  # qu'il manque une coordonnée.
  it "garde les comptes sans IBAN, en les marquant" do
    payables = described_class.new

    expect(payables.rows.size).to eq(2)
    expect(payables.without_iban.map(&:member_account)).to eq([compte_lino])
  end

  it "ignore un compte débiteur" do
    compte_zoe.account_entries.create!(entry_date: Date.current, kind: "bar", flow: "bar",
                                       label: "Bar", amount_cents: 5_000)

    expect(described_class.new.rows.map(&:member_account)).to eq([compte_lino])
  end
end
