# == Schema Information
#
# Table name: human_roles
#
#  id           :bigint           not null, primary key
#  date         :date
#  phone_holder :boolean          default(FALSE), not null
#  status       :integer          default(1), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  human_id     :bigint           not null
#  role_id      :bigint           not null
#
# Indexes
#
#  index_human_roles_on_human_id  (human_id)
#  index_human_roles_on_role_id   (role_id)
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#  fk_rails_...  (role_id => roles.id)
#
class HumanRole < ApplicationRecord
  belongs_to :human, -> { unscope(where: :deleted_at) }
  belongs_to :role

  validates :date, presence: true

  enum :status, { backup: 0, selected: 1 }

  # Plusieurs veilleurs le même jour : un seul tient le téléphone de la ligne
  # de garde (cf. `OnCall::Resolver`). Désigner l'un retire les autres.
  def make_phone_holder!
    transaction do
      HumanRole.where(role_id: role_id, date: date).where.not(id: id).update_all(phone_holder: false)
      update!(phone_holder: true)
    end
  end

  def has_watchman_note?
    # Vérifier si c'est un rôle de veilleur (role_id: 1) et s'il existe une note pour cette date
    role_id == 1 && WatchmanNote.exists?(date: date)
  end
end
