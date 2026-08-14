require "rails_helper"
# == Schema Information
#
# Table name: fiscal_years
#
#  id              :bigint           not null, primary key
#  closed_at       :datetime
#  deleted_at      :datetime
#  ends_on         :date             not null
#  starts_on       :date             not null
#  status          :string           default("open"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  legal_entity_id :bigint           not null
#
# Indexes
#
#  index_fiscal_years_on_deleted_at                     (deleted_at)
#  index_fiscal_years_on_legal_entity_id                (legal_entity_id)
#  index_fiscal_years_on_legal_entity_id_and_starts_on  (legal_entity_id,starts_on) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#
require Rails.root.join("spec/support/finance_builders")

# Deux exercices qui se chevauchent, c'est une écriture qui peut tomber dans
# deux exercices à la fois — et donc une balance qui dépend de l'ordre de
# lecture.
RSpec.describe FiscalYear do
  include FinanceBuilders

  let(:entity) { build_legal_entity }

  it "refuse un exercice qui en chevauche un autre pour la même entité" do
    build_fiscal_year(entity, year: 2026)
    doublon = described_class.new(legal_entity: entity, starts_on: Date.new(2026, 6, 1),
                                  ends_on: Date.new(2027, 5, 31))

    expect(doublon).not_to be_valid
    expect(doublon.errors.full_messages.join).to match(/chevauche/i)
  end

  it "autorise le même exercice pour une autre entité" do
    build_fiscal_year(entity, year: 2026)
    autre = build_legal_entity(name: "SRL de test", form: "srl")

    expect(described_class.new(legal_entity: autre, starts_on: Date.new(2026, 1, 1),
                               ends_on: Date.new(2026, 12, 31))).to be_valid
  end

  it "refuse une fin antérieure au début" do
    expect(described_class.new(legal_entity: entity, starts_on: Date.new(2026, 12, 31),
                               ends_on: Date.new(2026, 1, 1))).not_to be_valid
  end

  it "refuse de redater un exercice clôturé" do
    year = build_fiscal_year(entity, year: 2026)
    year.close!

    expect(year.update(ends_on: Date.new(2027, 6, 30))).to be(false)
    expect(year.errors.full_messages.join).to match(/ne se redate pas/i)
  end

  it "refuse de supprimer un exercice clôturé" do
    year = build_fiscal_year(entity, year: 2026)
    year.close!

    expect(year.destroy).to be(false)
    expect(described_class.find_by(id: year.id)).to be_present
  end

  it "sait quelle date il couvre" do
    year = build_fiscal_year(entity, year: 2026)

    expect(year.covers?(Date.new(2026, 6, 15))).to be(true)
    expect(year.covers?(Date.new(2027, 1, 1))).to be(false)
  end
end
