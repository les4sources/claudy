# == Schema Information
#
# Table name: bar_consumptions
#
#  id               :bigint           not null, primary key
#  deleted_at       :datetime
#  label            :string           not null
#  price_cents      :integer          not null
#  quantity         :integer          not null
#  unit_price_cents :integer          not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  catalog_item_id  :bigint           not null
#  stay_id          :bigint           not null
#
# Indexes
#
#  index_bar_consumptions_on_catalog_item_id     (catalog_item_id)
#  index_bar_consumptions_on_deleted_at          (deleted_at)
#  index_bar_consumptions_on_stay_and_item_live  (stay_id,catalog_item_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_bar_consumptions_on_stay_id             (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_item_id => catalog_items.id)
#  fk_rails_...  (stay_id => stays.id)
#
# Consommations du bar d'un groupe, rattachées à son séjour (Michael,
# 2026-10-13).
#
# Au bar, les groupes notent ce qu'ils prennent sur une feuille ; certains la
# rendent pour que tout soit facturé avec le séjour. Une ligne = un article du
# catalogue du bar et sa quantité, pour tout le séjour. Elle s'ajoute au total
# du séjour (`Stay#recompute_aggregates!`), donc à sa facture.
#
# Le prix unitaire est FIGÉ à l'encodage : c'est le prix public du catalogue à
# la date du séjour (`unit_price_for`). Un tarif qui change ensuite ne réécrit
# pas une facture déjà calculée.
class BarConsumption < ApplicationRecord
  CHANNEL = "bar".freeze

  belongs_to :stay
  belongs_to :catalog_item

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :unit_price_cents
  monetize :price_cents

  validates :label, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :catalog_item_is_bar

  before_validation :compute_price

  scope :ordered, -> { order(:label, :id) }

  # Les articles qu'on peut noter sur la feuille d'un séjour : ceux du bar.
  def self.catalog_items
    CatalogItem.for_channel(CHANNEL)
  end

  # Date à laquelle on lit le catalogue : l'arrivée du groupe. Encoder la
  # feuille d'un séjour de mars doit prendre les prix de mars.
  def self.price_date_for(stay)
    stay.arrival_date || Date.current
  end

  # Prix unitaire d'un article pour un groupe : le prix PUBLIC. Un article qui
  # n'en a pas (vendu jusqu'ici aux seuls habitants) prend le prix sourcier
  # plutôt que de rester impossible à facturer ; `public_price?` permet à
  # l'écran de le signaler. nil quand l'article n'a aucun prix à cette date.
  def self.unit_price_for(item, on:)
    price = item.price_on(on)
    return nil if price.nil?

    price.public_price_cents || price.member_price_cents
  end

  def self.public_price?(item, on:)
    item.price_on(on)&.public_price_cents.present?
  end

  private

  def compute_price
    self.price_cents = quantity.to_i * unit_price_cents.to_i
  end

  def catalog_item_is_bar
    return if catalog_item.nil? || catalog_item.channel == CHANNEL

    errors.add(:catalog_item, "n'est pas un article du bar")
  end
end
