require "rails_helper"

# Issue #155 — la composition d'un ménage se déduit toujours des périodes de
# présence. Recalculer « 10 €/adulte » pour mars 2024 ne doit pas mentir parce
# qu'un enfant est né depuis, ou qu'un colocataire est parti.
# == Schema Information
#
# Table name: households
#
#  id           :bigint           not null, primary key
#  deleted_at   :datetime
#  kind         :string           default("resident"), not null
#  moved_in_on  :date
#  moved_out_on :date
#  name         :string           not null
#  notes        :text
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_households_on_deleted_at  (deleted_at)
#
RSpec.describe Household, type: :model do
  let(:household) do
    Household.create!(name: "Famille Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1))
  end

  def add_member(name, kind:, started_on:, ended_on: nil)
    household.household_members.create!(name: name, kind: kind, started_on: started_on, ended_on: ended_on)
  end

  it "exige un nom et un type connu" do
    expect(Household.new(kind: "resident")).not_to be_valid
    expect(Household.new(name: "X", kind: "voisin")).not_to be_valid
  end

  it "refuse un départ antérieur à l'arrivée" do
    invalid = Household.new(name: "X", kind: "resident",
                            moved_in_on: Date.new(2024, 6, 1), moved_out_on: Date.new(2024, 5, 1))

    expect(invalid).not_to be_valid
    expect(invalid.errors[:moved_out_on]).to be_present
  end

  describe "#adults_on / #children_on" do
    before do
      add_member("Ada", kind: "adult", started_on: Date.new(2023, 1, 1))
      add_member("Bob", kind: "adult", started_on: Date.new(2023, 1, 1), ended_on: Date.new(2024, 6, 30))
      add_member("Zoé", kind: "child", started_on: Date.new(2025, 3, 12))
    end

    it "compte deux adultes et zéro enfant avant le départ de Bob et la naissance de Zoé" do
      expect(household.adults_on(Date.new(2024, 3, 1))).to eq(2)
      expect(household.children_on(Date.new(2024, 3, 1))).to eq(0)
    end

    it "compte encore Bob le jour même de son départ" do
      expect(household.adults_on(Date.new(2024, 6, 30))).to eq(2)
    end

    it "ne compte plus Bob le lendemain de son départ" do
      expect(household.adults_on(Date.new(2024, 7, 1))).to eq(1)
    end

    it "compte Zoé à partir de sa date d'entrée seulement" do
      expect(household.children_on(Date.new(2025, 3, 11))).to eq(0)
      expect(household.children_on(Date.new(2025, 3, 12))).to eq(1)
      expect(household.adults_on(Date.new(2025, 3, 12))).to eq(1)
    end

    it "ignore un membre supprimé" do
      household.household_members.find_by(name: "Ada").soft_delete!

      expect(household.adults_on(Date.new(2024, 3, 1))).to eq(1)
    end
  end

  it "refuse un membre dont la sortie précède l'entrée" do
    member = household.household_members.new(name: "X", kind: "adult",
                                             started_on: Date.new(2024, 6, 1), ended_on: Date.new(2024, 5, 1))

    expect(member).not_to be_valid
    expect(member.errors[:ended_on]).to be_present
  end

  it "trace les modifications avec PaperTrail" do
    expect { household.update!(name: "Famille Hulotte") }.to change { household.versions.count }.by(1)
  end
end
