require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #243, phase 3 — ce qu'un comptage refuse.
RSpec.describe CashCount do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let(:caisse_compte) { build_general_account(code: "570000", name: "Caisse") }
  let!(:caisse) { build_cash_account(entity, caisse_compte, name: "Caisse du domaine", kind: "cash") }

  def build_count(attributes = {})
    described_class.new({ cash_account: caisse, counted_on: Date.current, denominations: {},
                          counted_cents: 0, expected_cents: 0, difference_cents: 0 }.merge(attributes))
  end

  it "refuse un écart sans commentaire" do
    count = build_count(counted_cents: 10_000, expected_cents: 13_000, difference_cents: -3_000)

    expect(count).not_to be_valid
    expect(count.errors[:comment]).to be_present
  end

  it "accepte une caisse juste sans commentaire" do
    expect(build_count).to be_valid
  end

  it "refuse une issue inventée" do
    expect(build_count(resolution: "on_verra")).not_to be_valid
  end

  it "fige un comptage validé" do
    count = build_count(status: "validated", validated_at: Time.current)
    count.save!

    count.counted_cents = 99_999

    expect(count).not_to be_valid
    expect(count.errors[:base].join).to include("ne se modifie plus")
  end

  it "laisse un brouillon se corriger" do
    count = build_count(status: "draft")
    count.save!

    expect(count.update(counted_cents: 5_000, difference_cents: 5_000, comment: "Recompté")).to be(true)
  end

  describe ".total_cents" do
    it "additionne la grille" do
      expect(described_class.total_cents({ "50.00" => 2, "0.50" => 7 })).to eq(10_350)
    end

    it "ignore une coupure qui n'existe pas" do
      expect(described_class.total_cents({ "3.00" => 4 })).to eq(0)
    end
  end
end
