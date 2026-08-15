# Une ligne de trésorerie : un mouvement réel sur un compte bancaire, une caisse
# ou Stripe.
#
# C'est le SEUL point d'entrée d'une recette au journal. Les séjours, les
# paiements et les décomptes sont des documents que les allocations pointent ;
# les additionner en plus des lignes de trésorerie doublerait le chiffre
# d'affaires. Cette règle est la raison d'être de la table.
#
# Une ligne ne se détruit jamais. Un relevé bancaire est un fait : s'il est
# entré par erreur, on l'exclut avec un motif, ce qui laisse une trace de la
# décision. Supprimer effacerait la question au lieu d'y répondre.
# == Schema Information
#
# Table name: cash_entries
#
#  id                :bigint           not null, primary key
#  allocated_at      :datetime
#  amount_cents      :bigint           not null
#  communication     :string
#  counterparty_iban :string
#  counterparty_name :string
#  deleted_at        :datetime
#  entry_date        :date             not null
#  excluded_reason   :string
#  external_ref      :string
#  label             :string           not null
#  statement_ref     :string
#  status            :string           default("pending"), not null
#  transaction_code  :string
#  value_date        :date
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  cash_account_id   :bigint           not null
#
# Indexes
#
#  index_cash_entries_on_cash_account_id   (cash_account_id)
#  index_cash_entries_on_deleted_at        (deleted_at)
#  index_cash_entries_on_entry_date        (entry_date)
#  index_cash_entries_on_external_ref      (cash_account_id,external_ref) UNIQUE WHERE (external_ref IS NOT NULL)
#  index_cash_entries_on_status            (status)
#  index_cash_entries_on_transaction_code  (transaction_code)
#
# Foreign Keys
#
#  fk_rails_...  (cash_account_id => cash_accounts.id)
#
class CashEntry < ApplicationRecord
  STATUSES = %w[pending allocated excluded].freeze
  STATUS_LABELS = {
    "pending" => "À affecter",
    "allocated" => "Affectée",
    "excluded" => "Exclue"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :cash_account
  has_many :cash_allocations, dependent: :destroy
  has_many :allocation_suggestions, dependent: :destroy
  # Une ligne peut engendrer DEUX écritures quand une allocation appartient à
  # une autre entité : celle du mouvement, et son miroir chez l'entité tierce.
  # Un `has_one` en choisirait une au hasard.
  has_many :journal_entries, as: :source, dependent: :restrict_with_error

  monetize :amount_cents

  validates :entry_date, :label, presence: true
  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :excluded_reason, presence: true, if: -> { status == "excluded" }

  validate :frozen_once_posted, on: :update

  before_destroy :refuse_destruction

  scope :ordered, -> { order(entry_date: :desc, id: :desc) }
  scope :pending, -> { where(status: "pending") }
  scope :allocated, -> { where(status: "allocated") }
  scope :in_period, ->(from, to) { where(entry_date: from..to) }

  def status_label = STATUS_LABELS.fetch(status, status)
  def incoming? = amount_cents.positive?
  def allocated_cents = cash_allocations.sum(:amount_cents)
  def remaining_cents = amount_cents - allocated_cents
  def fully_allocated? = remaining_cents.zero?
  def posted? = journal_entries.any?

  # L'écriture du mouvement lui-même — celle qui touche la trésorerie.
  def journal_entry = journal_entries.find { |e| e.journal == journal }

  # Le journal suit le support : une caisse ne se lit pas comme une banque, et
  # le contrôle de caisse (lot C) a besoin de sa propre séquence.
  def journal = cash_account.kind == "cash" ? "cash" : "bank"

  # Exclure une ligne déjà comptabilisée laisserait son écriture au grand livre
  # sans rien qui la justifie. On annule la passation d'abord.
  def exclude!(reason)
    raise ArgumentError, "Cette ligne est comptabilisée — annule sa passation avant de l'exclure." if posted?

    update!(status: "excluded", excluded_reason: reason)
  end

  private

  # Une ligne comptabilisée décrit un mouvement dont l'écriture est déjà au
  # grand livre : changer son montant, son compte ou sa date ferait diverger les
  # deux sans que rien ne le signale.
  def frozen_once_posted
    return unless posted?
    return if (changed & %w[amount_cents cash_account_id entry_date]).empty?

    errors.add(:base, "Cette ligne est comptabilisée — annule sa passation avant de la modifier")
  end

  def refuse_destruction
    errors.add(:base, "Une ligne de trésorerie ne se supprime pas — exclus-la avec un motif")
    throw :abort
  end
end
