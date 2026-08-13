# == Schema Information
#
# Table name: account_settlements
#
#  id                :bigint           not null, primary key
#  amount_cents      :bigint           not null
#  bank_reference    :string
#  deleted_at        :datetime
#  method            :string           default("bank_transfer"), not null
#  notes             :text
#  received_channel  :string           default("bank"), not null
#  received_on       :date             not null
#  reference         :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_entry_id  :bigint
#  member_account_id :bigint           not null
#
# Indexes
#
#  index_account_settlements_on_account_entry_id   (account_entry_id)
#  index_account_settlements_on_deleted_at         (deleted_at)
#  index_account_settlements_on_member_account_id  (member_account_id)
#  index_account_settlements_on_received_on        (received_on)
#
# Foreign Keys
#
#  fk_rails_...  (account_entry_id => account_entries.id)
#  fk_rails_...  (member_account_id => member_accounts.id)
#
class AccountSettlement < ApplicationRecord
  METHODS = %w[cash bank_transfer compensation].freeze
  METHOD_LABELS = {
    "cash" => "Espèces",
    "bank_transfer" => "Virement",
    "compensation" => "Compensation"
  }.freeze

  # Le canal de RÉCEPTION, distinct du compte réglé : « 20 € dans la caisse de
  # l'épicerie pour le bar » est un cas réel, fréquent, et aujourd'hui
  # invérifiable faute d'endroit où l'écrire.
  CHANNELS = %w[bank bar_box grocery_box hand].freeze
  CHANNEL_LABELS = {
    "bank" => "Compte bancaire",
    "bar_box" => "Caisse du bar",
    "grocery_box" => "Caisse de l'épicerie",
    "hand" => "De la main à la main"
  }.freeze

  has_soft_deletion default_scope: true
  has_paper_trail

  belongs_to :member_account
  belongs_to :account_entry, optional: true

  monetize :amount_cents

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :received_on, presence: true
  validates :method, inclusion: { in: METHODS }
  validates :received_channel, inclusion: { in: CHANNELS }

  scope :recent_first, -> { order(received_on: :desc, id: :desc) }
  scope :unmatched, -> { where(member_account_id: nil) }

  def method_label = METHOD_LABELS.fetch(method, method)
  def channel_label = CHANNEL_LABELS.fetch(received_channel, received_channel)
end
