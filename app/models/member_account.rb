# == Schema Information
#
# Table name: member_accounts
#
#  id                    :bigint           not null, primary key
#  active                :boolean          default(TRUE), not null
#  code                  :string           not null
#  contact_email         :string
#  deleted_at            :datetime
#  kind                  :string           not null
#  name                  :string           not null
#  opening_balance_cents :bigint           default(0), not null
#  opening_balance_on    :date
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  household_id          :bigint
#  human_id              :bigint
#
# Indexes
#
#  index_member_accounts_on_code          (code) UNIQUE
#  index_member_accounts_on_deleted_at    (deleted_at)
#  index_member_accounts_on_household_id  (household_id)
#  index_member_accounts_on_human_id      (human_id)
#
# Foreign Keys
#
#  fk_rails_...  (household_id => households.id)
#  fk_rails_...  (human_id => humans.id)
#

# Un compte courant interne (issue #155).
#
# AUCUN SOLDE N'EST STOCKÉ. `balance_cents` est toujours recalculé depuis
# `opening_balance_cents` + la somme des écritures. Un solde stocké finit
# toujours par diverger de ses lignes, et on ne sait alors plus laquelle des
# deux valeurs ment.
#
# Un compte est ancré sur exactement une chose — un ménage, une personne, ou
# rien (`entity` : Semisto, Low tech, Collations…). L'invariant est tenu par une
# contrainte CHECK en base ; les validations ci-dessous ne font que le dire en
# français avant que la base ne le refuse.
#
# ⚠️ `Human` porte `default_scope -> { where(status: "active") }`. On ne joint
# donc JAMAIS `humans` depuis ici : le compte d'une personne partie doit rester
# lisible, avec son solde. C'est pour ça que `name` est NOT NULL sur le compte
# lui-même plutôt que dérivé de l'association.
class MemberAccount < ApplicationRecord
  KINDS = %w[household human entity].freeze

  KIND_LABELS = {
    "household" => "Ménage",
    "human"     => "Personne",
    "entity"    => "Entité"
  }.freeze

  CODE_PREFIX = "SRC-".freeze
  CODE_PATTERN = /\A#{CODE_PREFIX}\d+\z/

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :household, optional: true
  belongs_to :human, optional: true
  has_many :account_entries, dependent: :destroy

  monetize :opening_balance_cents

  before_validation :assign_code, on: :create

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :opening_balance_cents, numericality: { only_integer: true }
  validate :anchor_consistency

  scope :ordered, -> { order(:name) }
  scope :actives, -> { where(active: true) }
  scope :inactives, -> { where(active: false) }

  def kind_label = KIND_LABELS.fetch(kind, kind)

  # Solde = ouverture + somme des écritures. Jamais lu depuis une colonne.
  def balance_cents
    @balance_cents ||= opening_balance_cents + account_entries.sum(:amount_cents)
  end

  def entries_count
    @entries_count ||= account_entries.count
  end

  def last_entry_on
    @last_entry_on ||= account_entries.maximum(:entry_date)
  end

  # Injecte les agrégats calculés en UNE requête par `MemberAccounts::Summary`.
  # Sans ça, l'écran de liste ferait trois requêtes par compte.
  def prime_ledger!(entries_cents:, entries_count:, last_entry_on:)
    @balance_cents = opening_balance_cents + entries_cents
    @entries_count = entries_count
    @last_entry_on = last_entry_on
    self
  end

  # Séquence jamais réattribuée : on regarde AUSSI les comptes soft-deletés,
  # sinon supprimer le dernier compte recyclerait son code sur le suivant.
  def self.next_code
    used = with_deleted { where("code LIKE ?", "#{CODE_PREFIX}%").pluck(:code) }
    highest = used.filter_map { |code| code[CODE_PREFIX.length..].to_i if code.match?(CODE_PATTERN) }.max

    format("#{CODE_PREFIX}%04d", (highest || 0) + 1)
  end

  private

  def assign_code
    self.code = self.class.next_code if code.blank?
  end

  def anchor_consistency
    case kind
    when "household"
      errors.add(:household_id, "est obligatoire pour un compte de ménage") if household_id.blank?
      errors.add(:human_id, "doit rester vide pour un compte de ménage") if human_id.present?
    when "human"
      errors.add(:human_id, "est obligatoire pour un compte de personne") if human_id.blank?
      errors.add(:household_id, "doit rester vide pour un compte de personne") if household_id.present?
    when "entity"
      errors.add(:household_id, "doit rester vide pour une entité") if household_id.present?
      errors.add(:human_id, "doit rester vide pour une entité") if human_id.present?
    end
  end
end
