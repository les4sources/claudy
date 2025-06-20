# == Schema Information
#
# Table name: human_roles
#
#  id         :bigint           not null, primary key
#  human_id   :bigint           not null
#  role_id    :bigint           not null
#  date       :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class HumanRole < ApplicationRecord
  belongs_to :human, -> { unscope(where: :deleted_at) }
  belongs_to :role

  validates :date, presence: true

  def has_watchman_note?
    # Vérifier si c'est un rôle de veilleur (role_id: 1) et s'il existe une note pour cette date
    role_id == 1 && WatchmanNote.exists?(date: date)
  end
end
