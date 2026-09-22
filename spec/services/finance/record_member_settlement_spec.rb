require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Issue #349 — le règlement encaissé depuis une ligne bancaire entrante.
RSpec.describe Finance::RecordMemberSettlement do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4) }
  let!(:compte_bancaire) { build_cash_account(entity, banque) }
  let!(:bene) { Human.create!(name: "Bénédicte Lambert", email: "bene@les4sources.be") }
  let!(:compte) { MemberAccount.for_human!(bene) }

  # 75 € de frais mensuels dus.
  before do
    compte.account_entries.create!(entry_date: Date.new(2026, 9, 1), kind: "recurring", flow: "charges",
                                   label: "Frais mensuels", amount_cents: 7_500)
  end

  def entrante(cents, date: Date.new(2026, 9, 5), communication: "Frais mensuels septembre")
    entry = build_cash_entry(compte_bancaire, amount_cents: cents, entry_date: date, label: "Virement Béné")
    entry.update!(communication: communication)
    entry
  end

  describe "le geste double" do
    it "éteint la dette et affecte la ligne bancaire" do
      entry = entrante(7_500)

      described_class.new(member_account: compte, cash_entry: entry).run!

      expect(compte.reload.balance_cents).to eq(0)
      allocation = entry.reload.cash_allocations.first
      expect(allocation.general_account).to eq(clients)
      expect(allocation.amount_cents).to eq(7_500)
      expect(allocation.document).to eq(compte)
      expect(allocation.third_party.human).to eq(bene)
    end

    it "crée exactement une écriture négative et un règlement" do
      entry = entrante(7_500)

      described_class.new(member_account: compte, cash_entry: entry).run!

      reglements = compte.account_entries.where(kind: "settlement")
      expect(reglements.count).to eq(1)
      expect(reglements.first.amount_cents).to eq(-7_500)
      expect(compte.account_settlements.count).to eq(1)
      expect(entry.reload.cash_allocations.count).to eq(1)
    end

    it "comptabilise la ligne une fois entièrement affectée" do
      entry = entrante(7_500)

      described_class.new(member_account: compte, cash_entry: entry).run!

      expect(entry.reload.status).to eq("allocated")
      expect(entry.journal_entry).to be_present
    end

    # Six mois plus tard, il faut pouvoir dire d'où vient l'écriture.
    it "garde la communication brute et la ligne d'origine" do
      entry = entrante(7_500, communication: "SRC-0005 septembre")

      described_class.new(member_account: compte, cash_entry: entry).run!

      reglement = compte.account_settlements.last
      expect(reglement.reference).to eq("SRC-0005 septembre")
      expect(reglement.notes).to include("##{entry.id}")
      expect(reglement.method).to eq("bank_transfer")
      expect(reglement.received_on).to eq(Date.new(2026, 9, 5))
    end
  end

  describe "le montant imputé" do
    # Le geste courant : une ligne de 100 € sur une dette de 75 € n'impute que
    # 75 € — le reste appartient à autre chose.
    it "impute le minimum entre la ligne et la dette" do
      entry = entrante(10_000)

      described_class.new(member_account: compte, cash_entry: entry).run!

      expect(compte.reload.balance_cents).to eq(0)
      expect(entry.reload.cash_allocations.sum(:amount_cents)).to eq(7_500)
      expect(entry.remaining_cents).to eq(2_500)
    end

    it "accepte un règlement partiel" do
      entry = entrante(7_500)

      described_class.new(member_account: compte, cash_entry: entry, amount_cents: 3_000).run!

      expect(compte.reload.balance_cents).to eq(4_500)
      expect(entry.reload.cash_allocations.sum(:amount_cents)).to eq(3_000)
    end
  end

  describe "les refus" do
    it "refuse une ligne sortante" do
      entry = build_cash_entry(compte_bancaire, amount_cents: -7_500, label: "Virement émis")

      expect { described_class.new(member_account: compte, cash_entry: entry).run! }
        .to raise_error(described_class::WrongDirection, /ligne ENTRANTE/)
      expect(compte.reload.balance_cents).to eq(7_500)
    end

    it "refuse un montant supérieur à la dette" do
      entry = entrante(20_000)

      expect { described_class.new(member_account: compte, cash_entry: entry, amount_cents: 20_000).run! }
        .to raise_error(described_class::TooMuch, /ne doit que/)
      expect(entry.reload.cash_allocations).to be_empty
    end

    it "refuse un compte qui ne doit rien" do
      entry = entrante(7_500)
      compte.account_entries.destroy_all

      expect { described_class.new(member_account: compte.reload, cash_entry: entry).run! }
        .to raise_error(described_class::NotDebtor, /ne doit rien/)
      expect(entry.reload.cash_allocations).to be_empty
    end

    it "refuse un compte créditeur" do
      entry = entrante(7_500)
      compte.account_entries.create!(entry_date: Date.new(2026, 9, 2), kind: "settlement", flow: "other",
                                     label: "Trop-perçu", amount_cents: -20_000)

      expect { described_class.new(member_account: compte.reload, cash_entry: entry).run! }
        .to raise_error(described_class::NotDebtor)
    end

    it "refuse sans compte" do
      expect { described_class.new(member_account: nil, cash_entry: entrante(7_500)).run! }
        .to raise_error(described_class::MissingAccount)
    end
  end

  # Rejouer la même ligne sur le même compte ne doit pas créer un second
  # règlement : la contrainte d'unicité en base le refuse.
  it "ne double pas un règlement rejoué sur la même ligne" do
    entry = entrante(10_000)
    # Un règlement PARTIEL : le compte reste débiteur, donc le second appel
    # passe les refus métier et ne bute que sur la clé d'idempotence.
    described_class.new(member_account: compte, cash_entry: entry, amount_cents: 3_000).run!

    expect { described_class.new(member_account: compte.reload, cash_entry: entry.reload, amount_cents: 3_000).run! }
      .to raise_error(ActiveRecord::RecordNotUnique)

    expect(compte.reload.account_entries.where(kind: "settlement").count).to eq(1)
    expect(compte.account_settlements.count).to eq(1)
    expect(entry.reload.cash_allocations.count).to eq(1)
  end
end
