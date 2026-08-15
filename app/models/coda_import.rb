# Un fichier CODA déposé (issue #181).
#
# Le contenu brut est conservé. Ça coûte quelques dizaines de kilo-octets et ça
# permet de reparser plus tard sans redemander le fichier à la banque — utile le
# jour où le parseur apprend à lire un champ qu'il ignorait.
class CodaImport < ApplicationRecord
  STATUSES = %w[pending imported rejected].freeze
  STATUS_LABELS = {
    "pending" => "En attente",
    "imported" => "Importé",
    "rejected" => "Refusé"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :coda_statements, dependent: :destroy

  validates :filename, :sha256, :content, presence: true
  validates :sha256, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(created_at: :desc) }

  def status_label = STATUS_LABELS.fetch(status, status)
  def imported? = status == "imported"
  def rejected? = status == "rejected"
end
