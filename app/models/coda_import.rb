# Un fichier CODA déposé (issue #181).
#
# Le contenu brut est conservé. Ça coûte quelques dizaines de kilo-octets et ça
# permet de reparser plus tard sans redemander le fichier à la banque — utile le
# jour où le parseur apprend à lire un champ qu'il ignorait.
# == Schema Information
#
# Table name: coda_imports
#
#  id               :bigint           not null, primary key
#  content          :text             not null
#  creation_date    :date
#  deleted_at       :datetime
#  entries_count    :integer          default(0), not null
#  file_reference   :string
#  filename         :string           not null
#  imported_at      :datetime
#  report           :text
#  sha256           :string           not null
#  statements_count :integer          default(0), not null
#  status           :string           default("pending"), not null
#  whodunnit        :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_coda_imports_on_deleted_at  (deleted_at)
#  index_coda_imports_on_sha256      (sha256) UNIQUE
#
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
