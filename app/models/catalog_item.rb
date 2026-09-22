# == Schema Information
#
# Table name: catalog_items
#
#  id           :bigint           not null, primary key
#  active       :boolean          default(TRUE), not null
#  category     :string
#  channel      :string           not null
#  deleted_at   :datetime
#  name         :string           not null
#  reference    :string
#  unit         :string           default("piece"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  consignor_id :bigint
#
# Indexes
#
#  index_catalog_items_on_channel_and_name  (channel,name)
#  index_catalog_items_on_consignor_id      (consignor_id)
#  index_catalog_items_on_deleted_at        (deleted_at)
#
# Foreign Keys
#
#  fk_rails_...  (consignor_id => consignors.id)
#
# Article du bar, du cellier, des repas, de l'artisanat ou du pain (issue #157,
# epic #359 phase 1).
#
# L'article ne porte pas de prix : il a des paliers datés (`catalog_prices`).
# `price_on(date)` résout celui qui couvre la date demandée.
#
# Le canal `craft` est le seul qui appartienne à quelqu'un d'autre que la maison :
# un savon est le produit d'un artisan, pas un article des 4 Sources. D'où
# `consignor_id`, obligatoire sur ce canal et interdit sur les autres — sans quoi
# une vente d'artisanat ne saurait pas à qui la reverser.
class CatalogItem < ApplicationRecord
  CRAFT_CHANNEL = "craft".freeze

  CHANNELS = %w[bar grocery meal craft bread].freeze
  CHANNEL_LABELS = {
    "bar" => "Bar", "grocery" => "Cellier", "meal" => "Repas",
    CRAFT_CHANNEL => "Artisanat", "bread" => "Pain"
  }.freeze

  UNITS = %w[piece kg l portion day].freeze
  UNIT_LABELS = {
    "piece" => "pièce", "kg" => "kg", "l" => "litre",
    "portion" => "portion", "day" => "jour"
  }.freeze

  has_soft_deletion default_scope: true
  has_paper_trail

  belongs_to :consignor, optional: true

  has_many :catalog_prices, dependent: :destroy, inverse_of: :catalog_item
  has_many :account_entries, dependent: :nullify

  validates :name, presence: true
  validates :channel, inclusion: { in: CHANNELS }
  validates :unit, inclusion: { in: UNITS }
  validates :consignor_id,
            presence: { message: "est obligatoire pour un article d'artisanat" },
            if: :craft?
  validate :consignor_only_on_craft

  scope :ordered, -> { order(:channel, :name) }
  scope :active, -> { where(active: true) }
  scope :for_channel, ->(channel) { where(channel: channel) if channel.present? }
  scope :matching, ->(term) { where("catalog_items.name ILIKE ?", "%#{term}%") if term.present? }
  scope :for_consignor, ->(consignor) { where(consignor: consignor) }
  scope :craft, -> { where(channel: CRAFT_CHANNEL) }

  def craft? = channel == CRAFT_CHANNEL

  # Palier qui couvre `date`, ou nil. Passe par les paliers déjà chargés quand
  # ils le sont — l'écran de catalogue les précharge tous.
  def price_on(date)
    return nil if date.blank?

    if catalog_prices.loaded?
      catalog_prices.find { |price| price.covers?(date) }
    else
      catalog_prices.covering(date).first
    end
  end

  def current_price = price_on(Date.current)

  def prices_history
    catalog_prices.loaded? ? catalog_prices.sort_by(&:active_from).reverse
                           : catalog_prices.most_recent_first.to_a
  end

  def channel_label = CHANNEL_LABELS.fetch(channel, channel)
  def unit_label = UNIT_LABELS.fetch(unit, unit)

  private

  def consignor_only_on_craft
    return if craft? || consignor_id.blank?

    errors.add(:consignor_id, "ne se pose que sur un article d'artisanat")
  end
end
