# Une règle d'affectation : « quand une ligne ressemble à ceci, propose cela ».
#
# Le mot qui compte est PROPOSE. Une règle ne décide de rien, ne crée rien, et
# n'affecte aucun solde. Elle produit une suggestion motivée qu'un humain
# accepte ou refuse. C'est la différence entre un assistant et le défaut de
# Winbooks, où un code s'appliquait en silence et rangeait une recette
# d'hébergement dans le bar sans que personne ne le voie.
#
# Une règle sans aucun critère est INVALIDE. Elle matcherait tout, et ce serait
# exactement le compte par défaut qu'on refuse d'avoir — juste déguisé.
# == Schema Information
#
# Table name: allocation_rules
#
#  id                         :bigint           not null, primary key
#  accepted_count             :integer          default(0), not null
#  active                     :boolean          default(TRUE), not null
#  communication_contains     :string
#  confidence                 :integer          default(80), not null
#  counterparty_iban          :string
#  counterparty_name_contains :string
#  deleted_at                 :datetime
#  direction                  :string
#  label                      :string           not null
#  max_amount_cents           :bigint
#  min_amount_cents           :bigint
#  position                   :integer          default(0), not null
#  rejected_count             :integer          default(0), not null
#  transaction_code           :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  analytic_account_id        :bigint
#  general_account_id         :bigint           not null
#  legal_entity_id            :bigint           not null
#  team_id                    :bigint
#
# Indexes
#
#  index_allocation_rules_on_analytic_account_id  (analytic_account_id)
#  index_allocation_rules_on_deleted_at           (deleted_at)
#  index_allocation_rules_on_general_account_id   (general_account_id)
#  index_allocation_rules_on_legal_entity_id      (legal_entity_id)
#  index_allocation_rules_on_position             (position)
#  index_allocation_rules_on_team_id              (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (analytic_account_id => analytic_accounts.id)
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#
class AllocationRule < ApplicationRecord
  DIRECTIONS = %w[incoming outgoing].freeze
  DIRECTION_LABELS = { "incoming" => "Encaissements", "outgoing" => "Décaissements" }.freeze

  CRITERIA = %w[counterparty_iban counterparty_name_contains communication_contains
                transaction_code direction min_amount_cents max_amount_cents].freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :general_account
  belongs_to :analytic_account, optional: true
  belongs_to :team, optional: true
  belongs_to :legal_entity
  has_many :allocation_suggestions, dependent: :nullify

  validates :label, presence: true
  validates :confidence, inclusion: { in: 0..100 }
  validates :direction, inclusion: { in: DIRECTIONS }, allow_blank: true
  validate :at_least_one_criterion

  scope :ordered, -> { order(:position, :id) }
  scope :actives, -> { where(active: true) }

  def direction_label = direction.present? ? DIRECTION_LABELS.fetch(direction, direction) : "Les deux"

  # Rend le motif du match, ou nil. Le motif n'est pas décoratif : c'est ce qui
  # permet à un humain de juger une proposition sans rouvrir la configuration.
  def match(cash_entry)
    raisons = []

    if counterparty_iban.present?
      return nil unless normalize(cash_entry.counterparty_iban) == normalize(counterparty_iban)

      raisons << "IBAN #{counterparty_iban}"
    end

    if counterparty_name_contains.present?
      return nil unless cash_entry.counterparty_name.to_s.downcase.include?(counterparty_name_contains.downcase)

      raisons << "le tiers contient « #{counterparty_name_contains} »"
    end

    if communication_contains.present?
      return nil unless cash_entry.communication.to_s.downcase.include?(communication_contains.downcase)

      raisons << "la communication contient « #{communication_contains} »"
    end

    if transaction_code.present?
      return nil unless cash_entry.transaction_code.to_s.start_with?(transaction_code)

      raisons << "code transaction #{transaction_code}"
    end

    if direction.present?
      attendu = direction == "incoming"
      return nil unless cash_entry.incoming? == attendu

      raisons << direction_label.downcase
    end

    if min_amount_cents.present?
      return nil if cash_entry.amount_cents.abs < min_amount_cents

      raisons << "au moins #{Money.new(min_amount_cents, 'EUR').format}"
    end

    if max_amount_cents.present?
      return nil if cash_entry.amount_cents.abs > max_amount_cents

      raisons << "au plus #{Money.new(max_amount_cents, 'EUR').format}"
    end

    return nil if raisons.empty?

    "Règle « #{label} » : #{raisons.join(', ')}."
  end

  private

  def normalize(value) = value.to_s.gsub(/\s+/, "").upcase

  def at_least_one_criterion
    return if CRITERIA.any? { |criterion| public_send(criterion).present? }

    errors.add(:base, "Une règle sans aucun critère s'appliquerait à tout — c'est le compte par défaut " \
                      "qu'on refuse d'avoir. Ajoute au moins un critère.")
  end
end
