require "rails_helper"
# == Schema Information
#
# Table name: stripe_category_mappings
#
#  id                 :bigint           not null, primary key
#  account_key        :string           not null
#  category           :string
#  deleted_at         :datetime
#  notes              :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint           not null
#  legal_entity_id    :bigint
#  team_id            :bigint
#
# Indexes
#
#  index_stripe_category_mappings_on_account_and_category      (account_key,category) UNIQUE WHERE ((category IS NOT NULL) AND (deleted_at IS NULL))
#  index_stripe_category_mappings_on_account_without_category  (account_key) UNIQUE WHERE ((category IS NULL) AND (deleted_at IS NULL))
#  index_stripe_category_mappings_on_deleted_at                (deleted_at)
#  index_stripe_category_mappings_on_general_account_id        (general_account_id)
#  index_stripe_category_mappings_on_legal_entity_id           (legal_entity_id)
#  index_stripe_category_mappings_on_team_id                   (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 1 — l'affectation d'une catégorie de ventes Stripe se décide
# une fois, jamais transaction par transaction.
RSpec.describe StripeCategoryMapping, type: :model do
  include FinanceBuilders

  let!(:revenue) { build_general_account(code: "700100", name: "Ventes épicerie", klass: 7, nature: "revenue") }

  def build_mapping(category:, account: "tranche_de_vie")
    described_class.create!(account_key: account, category: category, general_account: revenue)
  end

  it "refuse deux correspondances pour la même catégorie sur le même compte" do
    build_mapping(category: "pain")

    doublon = described_class.new(account_key: "tranche_de_vie", category: "pain", general_account: revenue)
    expect(doublon).not_to be_valid
  end

  it "laisse la même catégorie exister sur un autre compte" do
    build_mapping(category: "pain")

    expect(build_mapping(category: "pain", account: "claudy")).to be_persisted
  end

  # « Sans catégorie » est une catégorie : elle se décide, et une seule fois.
  it "n'autorise qu'une seule correspondance « sans catégorie » par compte" do
    build_mapping(category: nil)

    second = described_class.new(account_key: "tranche_de_vie", category: nil, general_account: revenue)
    expect(second).not_to be_valid
    expect(second.errors[:base].join).to include("sans catégorie")
  end

  it "normalise une catégorie vide en « sans catégorie »" do
    mapping = build_mapping(category: "   ")

    expect(mapping.category).to be_nil
    expect(mapping.category_label).to eq("Sans catégorie")
  end

  describe ".for" do
    it "trouve la correspondance d'une catégorie, et celle du vide" do
      pain = build_mapping(category: "pain")
      sans = build_mapping(category: nil)

      expect(described_class.for("tranche_de_vie", "pain")).to eq(pain)
      expect(described_class.for("tranche_de_vie", " pain ")).to eq(pain)
      expect(described_class.for("tranche_de_vie", nil)).to eq(sans)
      expect(described_class.for("tranche_de_vie", "legumes")).to be_nil
    end
  end
end
