# Draps commandés pour un séjour (epic #260, phase 2 — décision Michael 6).
#
# Le site vend les draps 10 € par lit simple et 20 € par lit double. Ils n'ont ni
# date, ni occupation de calendrier : une ligne par TYPE de lit et par séjour,
# rattachée DIRECTEMENT au séjour (`has_many :linen_orders`), sur le modèle de
# `MealOrder` — donc pas de `StayItem`.
#
# Le montant vient du barème (`Pricing::Catalog.linen_rate`), la même source que
# la ligne `:linen` du devis : la part draps est extraite de `lodging_only_cents`,
# jamais ajoutée par-dessus. Aucun double-compte.
# == Schema Information
#
# Table name: linen_orders
#
#  id               :bigint           not null, primary key
#  deleted_at       :datetime
#  kind             :string           not null
#  price_cents      :integer
#  quantity         :integer          default(1), not null
#  unit_price_cents :integer
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  stay_id          :bigint           not null
#
# Indexes
#
#  index_linen_orders_on_deleted_at                 (deleted_at)
#  index_linen_orders_on_stay_and_kind_unique_live  (stay_id,kind) UNIQUE WHERE (deleted_at IS NULL)
#  index_linen_orders_on_stay_id                    (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (stay_id => stays.id)
#
class LinenOrder < ApplicationRecord
  KINDS = %w[single_bed double_bed].freeze

  KIND_LABELS = {
    "single_bed" => "Draps pour lit simple",
    "double_bed" => "Draps pour lit double"
  }.freeze

  belongs_to :stay

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :price_cents, allow_nil: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(Arel.sql("CASE kind WHEN 'single_bed' THEN 0 ELSE 1 END"), :id) }

  before_save :recompute_price

  def self.label_for(kind) = KIND_LABELS[kind.to_s] || kind.to_s.tr("_", " ").capitalize

  def label = self.class.label_for(kind)

  # Tarif unitaire appliqué : l'override de la ligne d'abord, le barème ensuite.
  def unit_price_effective_cents
    unit_price_cents || Pricing::Catalog.linen_rate(kind).to_i
  end

  private

  # `price_cents` reste le TOTAL de la ligne. Un total posé explicitement dans la
  # MÊME sauvegarde fait foi — c'est la ventilation du devis persistée telle quelle.
  def recompute_price
    return if will_save_change_to_price_cents? && price_cents.present?
    return unless price_cents.nil? || will_save_change_to_quantity? ||
                  will_save_change_to_kind? || will_save_change_to_unit_price_cents?

    self.price_cents = unit_price_effective_cents * quantity.to_i
  end
end
