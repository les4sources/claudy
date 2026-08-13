# == Schema Information
#
# Table name: catalog_prices
#
#  id                    :bigint           not null, primary key
#  active_from           :date             not null
#  active_until          :date
#  member_price_cents    :integer          not null
#  note                  :string
#  public_price_cents    :integer
#  purchase_price_cents  :integer
#  reference_price_cents :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  catalog_item_id       :bigint           not null
#
# Indexes
#
#  index_catalog_prices_on_catalog_item_id                  (catalog_item_id)
#  index_catalog_prices_on_catalog_item_id_and_active_from  (catalog_item_id,active_from) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (catalog_item_id => catalog_items.id)
#
# Palier de prix daté d'un article (issue #157).
#
# Même sémantique de période que `RateVersion` (#156) : `[active_from,
# active_until]`, bornes incluses, `active_until = nil` pour « jusqu'à nouvel
# ordre », et interdiction de chevauchement — sinon `price_on(date)` n'aurait
# plus de réponse unique.
#
# Les quatre prix sont stockés, aucun n'est recalculé à la lecture. Seul
# `member_price_cents` est obligatoire : c'est le seul dont le compte sourcier
# a besoin. Le prix d'achat manque parfois (don, récupération), le prix public
# n'existe pas pour un article qui n'est pas vendu au public.
class CatalogPrice < ApplicationRecord
  belongs_to :catalog_item, inverse_of: :catalog_prices

  monetize :member_price_cents
  monetize :purchase_price_cents, allow_nil: true
  monetize :reference_price_cents, allow_nil: true
  monetize :public_price_cents, allow_nil: true

  validates :active_from, presence: true
  validates :member_price_cents,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :active_until_after_active_from
  validate :no_overlap_with_siblings

  scope :chronological, -> { order(active_from: :asc) }
  scope :most_recent_first, -> { order(active_from: :desc) }

  scope :covering, lambda { |date|
    where(active_from: ..date)
      .where("catalog_prices.active_until IS NULL OR catalog_prices.active_until >= ?", date)
  }

  def covers?(date)
    return false if active_from.nil? || date.nil?

    active_from <= date && (active_until.nil? || active_until >= date)
  end

  def current? = covers?(Date.current)

  def open_ended? = active_until.nil?

  private

  def active_until_after_active_from
    return if active_until.blank? || active_from.blank?
    return if active_until >= active_from

    errors.add(:active_until, "doit être postérieure ou égale à la date de début")
  end

  def no_overlap_with_siblings
    return if catalog_item_id.blank? || active_from.blank?

    if siblings.covering(active_from).exists?
      return errors.add(:active_from, "chevauche un palier existant de cet article")
    end

    later = active_until.blank? ? siblings.where(active_from: active_from..)
                                : siblings.where(active_from: active_from..active_until)
    return unless later.exists?

    errors.add(:active_until, "chevauche un palier existant de cet article")
  end

  def siblings
    scope = CatalogPrice.where(catalog_item_id: catalog_item_id)
    persisted? ? scope.where.not(id: id) : scope
  end
end
