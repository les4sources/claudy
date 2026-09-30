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
#  third_party_id        :bigint
#
# Indexes
#
#  index_catalog_prices_on_catalog_item_id                  (catalog_item_id)
#  index_catalog_prices_on_catalog_item_id_and_active_from  (catalog_item_id,active_from) UNIQUE
#  index_catalog_prices_on_third_party_id                   (third_party_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_item_id => catalog_items.id)
#  fk_rails_...  (third_party_id => third_parties.id)
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
  # Le fournisseur chez qui ce prix d'achat a été relevé — un tiers de la
  # comptabilité, jamais une liste parallèle. Facultatif : l'historique repris du
  # fichier Excel du cellier n'en a pas.
  belongs_to :third_party, optional: true

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
  validate :third_party_is_supplier

  # Marge sur le COÛT : (public − achat) ÷ achat (Michael, 2026-09-30). Objectif
  # 30 % ; sous 25 % elle s'affiche en rouge, jusqu'à 28 % en orange, au-delà
  # en vert. Le prix de vente conseillé applique l'objectif au prix d'achat.
  MARGIN_TARGET = 30
  MARGIN_MINIMUM = 25
  MARGIN_COMFORT = 28

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

  def self.recommended_public_cents(purchase_cents)
    return nil if purchase_cents.blank? || purchase_cents.to_i <= 0

    (purchase_cents.to_i * (1 + MARGIN_TARGET / 100.0)).round
  end

  # En pourcentage entier, arrondi — c'est ce nombre-là qu'on lit, c'est donc
  # lui qui décide de la couleur. Nil sans prix d'achat ou sans prix public.
  def margin_percent
    return nil if purchase_price_cents.blank? || purchase_price_cents <= 0 || public_price_cents.blank?

    ((public_price_cents - purchase_price_cents) * 100.0 / purchase_price_cents).round
  end

  def margin_level
    percent = margin_percent
    return nil if percent.nil?
    return :low if percent < MARGIN_MINIMUM
    return :medium if percent < MARGIN_COMFORT

    :good
  end

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

  def third_party_is_supplier
    return if third_party.nil? || third_party.kind.in?(%w[supplier both])

    errors.add(:third_party, "doit être un tiers fournisseur, pas un client")
  end

  def siblings
    scope = CatalogPrice.where(catalog_item_id: catalog_item_id)
    persisted? ? scope.where.not(id: id) : scope
  end
end
