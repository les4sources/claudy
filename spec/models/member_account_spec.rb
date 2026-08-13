require "rails_helper"

# Issue #155 — le compte courant. Deux invariants sont testés au niveau de la
# BASE, pas du modèle : l'ancrage (contrainte CHECK) et l'absence de colonne de
# solde. Une validation Ruby se contourne ; une contrainte, non.
RSpec.describe MemberAccount, type: :model do
  let(:household) { Household.create!(name: "Famille Chevêche", kind: "resident") }
  let(:human) { Human.create!(name: "Ada Lovelace", status: "active") }

  def account(attrs = {})
    MemberAccount.new({ kind: "entity", name: "Semisto" }.merge(attrs))
  end

  describe "ancrage" do
    it "accepte les trois formes valides" do
      expect(account(kind: "household", name: "Chevêche", household_id: household.id)).to be_valid
      expect(account(kind: "human", name: "Ada", human_id: human.id)).to be_valid
      expect(account(kind: "entity", name: "Semisto")).to be_valid
    end

    it "refuse en Ruby un compte de ménage sans ménage" do
      invalid = account(kind: "household", name: "Chevêche")

      expect(invalid).not_to be_valid
      expect(invalid.errors[:household_id]).to be_present
    end

    it "refuse en Ruby une entité ancrée" do
      expect(account(kind: "entity", household_id: household.id)).not_to be_valid
      expect(account(kind: "entity", human_id: human.id)).not_to be_valid
    end

    # Validations contournées : c'est la contrainte CHECK qui doit tenir.
    [
      { kind: "household", household: false, human: false },
      { kind: "household", household: true,  human: true },
      { kind: "human",     household: false, human: false },
      { kind: "human",     household: true,  human: true },
      { kind: "entity",    household: true,  human: false },
      { kind: "entity",    household: false, human: true }
    ].each_with_index do |combo, index|
      it "refuse EN BASE #{combo[:kind]} (ménage: #{combo[:household]}, personne: #{combo[:human]})" do
        record = MemberAccount.new(
          kind: combo[:kind],
          name: "Bancal",
          code: "SRC-90#{index}0",
          household_id: combo[:household] ? household.id : nil,
          human_id: combo[:human] ? human.id : nil
        )

        expect { record.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end
  end

  describe "code" do
    it "s'attribue au format SRC-0001 et s'incrémente" do
      first = MemberAccount.create!(kind: "entity", name: "Semisto")
      second = MemberAccount.create!(kind: "entity", name: "Low tech")

      expect(first.code).to eq("SRC-0001")
      expect(second.code).to eq("SRC-0002")
    end

    it "n'est jamais réattribué, même après suppression du dernier compte" do
      MemberAccount.create!(kind: "entity", name: "Semisto")
      MemberAccount.create!(kind: "entity", name: "Low tech").soft_delete!

      expect(MemberAccount.create!(kind: "entity", name: "Collations").code).to eq("SRC-0003")
    end

    it "reste unique" do
      MemberAccount.create!(kind: "entity", name: "Semisto")
      duplicate = MemberAccount.new(kind: "entity", name: "Autre", code: "SRC-0001")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:code]).to be_present
    end
  end

  describe "#balance_cents" do
    let(:record) do
      MemberAccount.create!(kind: "entity", name: "Semisto",
                            opening_balance_cents: 5_000, opening_balance_on: Date.new(2024, 1, 1))
    end

    it "vaut l'ouverture quand il n'y a aucune écriture" do
      expect(record.balance_cents).to eq(5_000)
    end

    it "additionne les écritures, y compris négatives" do
      record.account_entries.create!(entry_date: Date.new(2024, 2, 1), amount_cents: 1_250, label: "Bar")
      record.account_entries.create!(entry_date: Date.new(2024, 3, 1), amount_cents: -3_000, label: "Règlement")

      expect(record.reload.balance_cents).to eq(5_000 + 1_250 - 3_000)
    end

    it "ne s'appuie sur aucune colonne de solde" do
      expect(MemberAccount.column_names.grep(/balance/)).to eq(%w[opening_balance_cents opening_balance_on])
    end

    it "ignore les écritures supprimées" do
      entry = record.account_entries.create!(entry_date: Date.new(2024, 2, 1), amount_cents: 1_250)
      entry.soft_delete!

      expect(record.reload.balance_cents).to eq(5_000)
    end
  end

  # `Human` porte `default_scope -> { where(status: "active") }` : un compte
  # ancré sur une personne désactivée ne doit pas disparaître de l'écran.
  describe "compte d'une personne partie" do
    it "reste listable et lisible avec son solde" do
      record = MemberAccount.create!(kind: "human", name: "Ada Lovelace", human_id: human.id)
      record.account_entries.create!(entry_date: Date.current, amount_cents: 2_400, label: "Bar")

      human.update_column(:status, "inactive")

      expect(MemberAccount.ordered.to_a).to include(record)
      expect(MemberAccount.find(record.id).name).to eq("Ada Lovelace")
      expect(MemberAccount.find(record.id).balance_cents).to eq(2_400)
    end
  end

  describe "MemberAccounts::Summary" do
    it "calcule tous les soldes en une seule requête et trie par solde décroissant" do
      poor = MemberAccount.create!(kind: "entity", name: "A")
      rich = MemberAccount.create!(kind: "entity", name: "B", opening_balance_cents: 1_000)
      rich.account_entries.create!(entry_date: Date.new(2024, 5, 2), amount_cents: 4_000)
      rich.account_entries.create!(entry_date: Date.new(2024, 5, 9), amount_cents: 1_000)
      poor.account_entries.create!(entry_date: Date.new(2024, 5, 1), amount_cents: -500)

      rows = MemberAccounts::Summary.new(MemberAccount.ordered).accounts

      expect(rows.map(&:name)).to eq(%w[B A])
      expect(rows.first.balance_cents).to eq(6_000)
      expect(rows.first.entries_count).to eq(2)
      expect(rows.first.last_entry_on).to eq(Date.new(2024, 5, 9))
      expect(rows.last.balance_cents).to eq(-500)
    end

    it "ne fait qu'une requête d'agrégat quel que soit le nombre de comptes" do
      3.times { |i| MemberAccount.create!(kind: "entity", name: "E#{i}") }

      queries = 0
      counter = ->(*, payload) { queries += 1 if payload[:sql].include?("account_entries") }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        MemberAccounts::Summary.new(MemberAccount.ordered).accounts
      end

      expect(queries).to eq(1)
    end
  end
end
