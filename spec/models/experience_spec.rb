# == Schema Information
#
# Table name: experiences
#
#  id                :bigint           not null, primary key
#  name              :string
#  human_id          :bigint
#  summary           :string
#  description       :text
#  photo             :string
#  deleted_at        :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  price_cents       :integer
#  fixed_price_cents :integer          default(0)
#  min_participants  :integer
#  max_participants  :integer
#  duration          :string
#  duration_hours    :decimal(, )
#
require 'rails_helper'

# Phase 3 de l'épic #25 — durée numérique en heures sur Experience.
RSpec.describe Experience, type: :model do
  describe "duration_hours" do
    it "accepte une valeur décimale positive" do
      experience = Experience.new(name: "Atelier vannerie", duration_hours: 2.5)
      expect(experience).to be_valid
    end

    it "accepte l'absence de valeur (nil)" do
      experience = Experience.new(name: "Balade contée")
      expect(experience).to be_valid
    end

    it "rejette une valeur nulle ou négative" do
      expect(Experience.new(name: "X", duration_hours: 0)).not_to be_valid
      expect(Experience.new(name: "Y", duration_hours: -1)).not_to be_valid
    end
  end

  describe "#block_duration_minutes" do
    it "convertit les heures en minutes" do
      expect(Experience.new(duration_hours: 2.5).block_duration_minutes).to eq(150)
      expect(Experience.new(duration_hours: 1).block_duration_minutes).to eq(60)
    end

    it "renvoie nil sans durée numérique" do
      expect(Experience.new.block_duration_minutes).to be_nil
    end
  end
end
