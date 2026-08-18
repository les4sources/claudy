# == Schema Information
#
# Table name: account_entries
#
#  id                   :bigint           not null, primary key
#  amount_cents         :bigint           not null
#  client_uuid          :string
#  deleted_at           :datetime
#  entry_date           :date             not null
#  flow                 :string
#  idempotency_key      :string
#  kind                 :string
#  label                :string
#  locked_at            :datetime
#  posted_at            :datetime
#  price_basis          :string
#  quantity             :decimal(12, 3)
#  source               :string
#  unit_price_cents     :integer
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_statement_id :bigint
#  catalog_item_id      :bigint
#  member_account_id    :bigint           not null
#  paper_sheet_id       :bigint
#  reversal_of_id       :bigint
#
# Indexes
#
#  index_account_entries_on_account_statement_id              (account_statement_id)
#  index_account_entries_on_catalog_item_id                   (catalog_item_id)
#  index_account_entries_on_client_uuid                       (client_uuid) UNIQUE
#  index_account_entries_on_deleted_at                        (deleted_at)
#  index_account_entries_on_idempotency_key                   (idempotency_key) UNIQUE
#  index_account_entries_on_member_account_id_and_entry_date  (member_account_id,entry_date)
#  index_account_entries_on_paper_sheet_id                    (paper_sheet_id)
#  index_account_entries_on_reversal_of_id                    (reversal_of_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_statement_id => account_statements.id)
#  fk_rails_...  (catalog_item_id => catalog_items.id)
#  fk_rails_...  (member_account_id => member_accounts.id)
#  fk_rails_...  (paper_sheet_id => paper_sheets.id)
#  fk_rails_...  (reversal_of_id => account_entries.id)
#

# Une ligne du grand livre (issue #155).
#
# Le montant est SIGNÉ : positif = dû par le compte, négatif = en sa faveur
# (règlement, avoir). Zéro n'existe pas — la base le refuse.
#
# UNE ÉCRITURE RATTACHÉE À UN DÉCOMPTE ÉMIS EST IMMUABLE. `update` comme
# `destroy` lèvent `AccountEntry::Locked`, y compris depuis une console : sans
# cette règle, un décompte envoyé par mail peut se mettre à mentir après coup et
# le grand livre n'est plus auditable. La seule correction possible est une
# contre-écriture (`#reverse!`).
class AccountEntry < ApplicationRecord
  # Levée dès qu'on tente de toucher une écriture verrouillée.
  class Locked < StandardError; end

  FLOWS = %w[bar grocery meal pot dome pet charges other].freeze

  FLOW_LABELS = {
    "bar"     => "Bar",
    "grocery" => "Épicerie",
    "meal"    => "Repas",
    "pot"     => "Cagnotte",
    "dome"    => "Dôme",
    "pet"     => "Animaux",
    "charges" => "Charges",
    "other"   => "Divers"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :member_account
  # La colonne et sa clé étrangère existent depuis l'encodage des fiches
  # papier ; l'association manquait, si bien que remonter d'une écriture à
  # l'article vendu imposait une seconde requête écrite à la main.
  belongs_to :catalog_item, optional: true
  belongs_to :reversal_of, class_name: "AccountEntry", optional: true
  has_one :reversal, class_name: "AccountEntry", foreign_key: :reversal_of_id,
                     inverse_of: :reversal_of

  monetize :amount_cents

  validates :entry_date, presence: true
  validates :amount_cents,
            presence: true,
            numericality: { only_integer: true, other_than: 0 }
  validates :flow, inclusion: { in: FLOWS }, allow_blank: true

  before_update :refuse_when_locked
  before_destroy :refuse_when_locked

  scope :recent_first, -> { order(entry_date: :desc, id: :desc) }
  scope :chronological, -> { order(entry_date: :asc, id: :asc) }

  def locked? = account_statement_id.present? || locked_at.present?

  def flow_label = FLOW_LABELS.fetch(flow, flow)

  # Contre-écriture : montant opposé, datée d'aujourd'hui, qui pointe vers
  # l'originale. L'originale n'est JAMAIS modifiée — c'est tout l'intérêt.
  def reverse!(label: nil)
    member_account.account_entries.create!(
      entry_date: Date.current,
      amount_cents: -amount_cents,
      kind: "reversal",
      reversal_of_id: id,
      flow: flow,
      source: source,
      label: label.presence || "Contre-écriture — #{self.label}"
    )
  end

  private

  # On regarde l'état PERSISTÉ, pas l'état en mémoire : poser le verrou
  # (rattacher un décompte, renseigner `locked_at`) reste possible une fois,
  # tout ce qui suit est refusé.
  def refuse_when_locked
    return unless persisted_lock?

    raise Locked, "L'écriture ##{id} est rattachée à un décompte émis : " \
                  "elle ne peut plus être modifiée ni supprimée. Passe par une contre-écriture."
  end

  def persisted_lock?
    account_statement_id_in_database.present? || locked_at_in_database.present?
  end
end
