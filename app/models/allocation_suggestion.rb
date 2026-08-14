# Une proposition d'affectation, faite par une règle ou par le précédent d'un
# même IBAN.
#
# Table séparée des allocations, et c'est délibéré : une suggestion n'est pas
# une affectation en attente, c'est une proposition. La séparation rend
# impossible qu'une suggestion pèse sur un solde par accident — un champ
# `pending` sur `cash_allocations` aurait fini par être oublié dans une somme.
# == Schema Information
#
# Table name: allocation_suggestions
#
#  id                  :bigint           not null, primary key
#  amount_cents        :bigint           not null
#  confidence          :integer          default(50), not null
#  decided_at          :datetime
#  decided_by          :string
#  deleted_at          :datetime
#  rationale           :text             not null
#  source              :string           default("rule"), not null
#  status              :string           default("pending"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  allocation_rule_id  :bigint
#  analytic_account_id :bigint
#  cash_entry_id       :bigint           not null
#  general_account_id  :bigint           not null
#  legal_entity_id     :bigint           not null
#  team_id             :bigint
#
# Indexes
#
#  index_allocation_suggestions_on_allocation_rule_id        (allocation_rule_id)
#  index_allocation_suggestions_on_analytic_account_id       (analytic_account_id)
#  index_allocation_suggestions_on_cash_entry_id             (cash_entry_id)
#  index_allocation_suggestions_on_cash_entry_id_and_status  (cash_entry_id,status)
#  index_allocation_suggestions_on_deleted_at                (deleted_at)
#  index_allocation_suggestions_on_general_account_id        (general_account_id)
#  index_allocation_suggestions_on_legal_entity_id           (legal_entity_id)
#  index_allocation_suggestions_on_team_id                   (team_id)
#  index_one_pending_suggestion_per_entry                    (cash_entry_id) UNIQUE WHERE (((status)::text = 'pending'::text) AND (deleted_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (allocation_rule_id => allocation_rules.id)
#  fk_rails_...  (analytic_account_id => analytic_accounts.id)
#  fk_rails_...  (cash_entry_id => cash_entries.id)
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#
class AllocationSuggestion < ApplicationRecord
  STATUSES = %w[pending accepted rejected].freeze
  STATUS_LABELS = {
    "pending" => "Proposée",
    "accepted" => "Acceptée",
    "rejected" => "Refusée"
  }.freeze

  SOURCES = %w[rule iban_history].freeze
  SOURCE_LABELS = { "rule" => "Règle", "iban_history" => "Précédent" }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :cash_entry
  belongs_to :allocation_rule, optional: true
  belongs_to :general_account
  belongs_to :analytic_account, optional: true
  belongs_to :team, optional: true
  belongs_to :legal_entity

  monetize :amount_cents

  validates :rationale, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :confidence, inclusion: { in: 0..100 }

  scope :pending, -> { where(status: "pending") }
  scope :ordered, -> { order(confidence: :desc, id: :asc) }
  scope :confident_from, ->(threshold) { where("confidence >= ?", threshold) }

  def status_label = STATUS_LABELS.fetch(status, status)
  def source_label = SOURCE_LABELS.fetch(source, source)
end
