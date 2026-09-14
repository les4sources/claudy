# Une notification adressée à UN utilisateur (epic #242, phase 2, décision 2).
#
# Elle dit trois choses : ce qui s'est passé (`title`, `body`), qui l'a fait
# (`actor`, facultatif) et **où aller** (`url`, obligatoire). C'est la dernière
# qui la distingue du flux « Activité récente » : une notification sans
# destination est une impasse, donc elle est refusée.
#
# ⚠️ Point de création UNIQUE : `Notifications::Notify`. Rien d'autre dans
# `app/` n'appelle `Notification.new` ou `.create` — c'est ce qui garantit
# qu'une notification part toujours avec son email et sa trace. Une spec le
# vérifie (`spec/services/notifications/notify_spec.rb`).
class Notification < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :actor, class_name: "User", optional: true
  # L'objet peut disparaître (soft-delete, purge) : la notification reste
  # lisible grâce à son titre et son corps, figés à la création.
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :kind, :title, :url, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :for_recipient, ->(user) { where(recipient_id: user&.id) }

  def read? = read_at.present?

  # Idempotent : rouvrir une notification déjà lue ne redate rien.
  def mark_read!
    return if read?

    update_column(:read_at, Time.current)
  end

  def emailed? = emailed_at.present?
end
