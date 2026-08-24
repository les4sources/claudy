# Le document d'origine d'une écriture reprise d'un système extérieur.
#
# Il ne sert pas à rejouer la comptabilité : il sert à ce qu'on puisse relancer
# une reprise sans la doubler. `Accounting::PostDocument` refuse déjà de passer
# deux fois le même `source` dans le même journal ; ce modèle est le `source`
# que la reprise Winbooks n'avait pas — une facture de 2023 n'existe nulle part
# ailleurs dans Claudy.
#
# `external_ref` est l'identité du document dans le système d'origine, exercice
# et journal compris (`winbooks:2024:ACHATS:261`). Une clé plus courte laisserait
# deux documents différents se confondre — c'est l'erreur qui a coûté 720 € lors
# de la reprise du Synology en août 2026.
#
# `payload` garde la ligne brute telle qu'elle a été lue. Quand un total ne
# tombera pas juste dans deux ans, c'est la seule chose qui permettra de savoir
# si l'erreur vient de la lecture ou de la source.
# == Schema Information
#
# Table name: ledger_documents
#
#  id            :bigint           not null, primary key
#  deleted_at    :datetime
#  document_date :date             not null
#  external_ref  :string           not null
#  label         :string           not null
#  payload       :jsonb            not null
#  source_system :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_ledger_documents_on_deleted_at                      (deleted_at)
#  index_ledger_documents_on_source_system_and_external_ref  (source_system,external_ref) UNIQUE
#
class LedgerDocument < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :journal_entries, as: :source, dependent: :restrict_with_error

  validates :source_system, presence: true
  validates :external_ref, presence: true, uniqueness: { scope: :source_system }
  validates :document_date, presence: true
  validates :label, presence: true

  scope :ordered, -> { order(:document_date, :external_ref) }
  scope :imported_from, ->(system) { where(source_system: system) }

  def to_s = "#{source_system}:#{external_ref}"
end
