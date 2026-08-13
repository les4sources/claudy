# == Schema Information
#
# Table name: users
#
#  id                        :bigint           not null, primary key
#  email                     :string           default(""), not null
#  encrypted_password        :string           default(""), not null
#  remember_created_at       :datetime
#  reset_password_sent_at    :datetime
#  reset_password_token      :string
#  restricted_to_experiences :boolean          default(FALSE), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  human_id                  :bigint
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_human_id              (human_id)
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#
require 'rails_helper'

RSpec.describe User, type: :model do
  describe "restricted_to_experiences" do
    it "vaut false par défaut (comptes existants inchangés)" do
      user = User.create!(email: "libre@example.com", password: "password123")
      expect(user.restricted_to_experiences?).to be(false)
    end
  end

  describe "blocage des comptes de membres désactivés" do
    it "un compte admin (sans human) reste toujours actif" do
      user = User.create!(email: "admin@example.com", password: "password123")
      expect(user.member_deactivated?).to be(false)
      expect(user.active_for_authentication?).to be(true)
    end

    it "un compte lié à un membre actif reste connectable" do
      human = Human.create!(name: "Membre Actif", status: "active")
      user = User.create!(email: "actif@example.com", password: "password123", human: human)
      expect(user.member_deactivated?).to be(false)
      expect(user.active_for_authentication?).to be(true)
    end

    it "un compte lié à un membre inactif ne peut plus s'authentifier" do
      human = Human.create!(name: "Membre Inactif")
      human.update_column(:status, "inactive")
      user = User.create!(email: "inactif@example.com", password: "password123", human_id: human.id)

      # `user.human` est masqué par le default_scope (status active) : on doit
      # passer par linked_human (unscoped) pour détecter la désactivation.
      expect(user.human).to be_nil
      expect(user.linked_human).to eq(human)
      expect(user.member_deactivated?).to be(true)
      expect(user.active_for_authentication?).to be(false)
      expect(user.inactive_message).to eq(:account_deactivated)
    end
  end
end
