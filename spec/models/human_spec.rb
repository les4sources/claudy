# == Schema Information
#
# Table name: humans
#
#  id          :bigint           not null, primary key
#  name        :string
#  email       :string
#  photo       :string
#  summary     :string
#  description :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  status      :string           default("active")
#
require 'rails_helper'

RSpec.describe Human, type: :model do
  describe "roles_enabled" do
    it "vaut true par défaut (données existantes inchangées)" do
      human = Human.create!(name: "Membre Par Défaut")
      expect(human.roles_enabled).to be(true)
    end

    describe ".roles_enabled scope" do
      it "ne renvoie que les membres dont la gestion des rôles est activée" do
        with_roles    = Human.create!(name: "Avec Rôles", roles_enabled: true)
        without_roles = Human.create!(name: "Sans Rôles", roles_enabled: false)

        result = Human.roles_enabled
        expect(result).to include(with_roles)
        expect(result).not_to include(without_roles)
      end
    end
  end
end
