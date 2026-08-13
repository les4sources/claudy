# == Schema Information
#
# Table name: meal_orders
#
#  id          :bigint           not null, primary key
#  date        :date
#  deleted_at  :datetime
#  kind        :string
#  people      :integer          default(1), not null
#  price_cents :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  stay_id     :bigint           not null
#
# Indexes
#
#  index_meal_orders_on_deleted_at  (deleted_at)
#  index_meal_orders_on_stay_id     (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (stay_id => stays.id)
#
# Commande de REPAS — epic #66, Phase 3. Rattachée DIRECTEMENT au séjour
# (`has_many` sur Stay, comme `ExperienceBooking`), PAS via `StayItem` : un repas
# n'occupe pas le calendrier. Modèle daté `{kind, date, people}` ; `date` est
# nullable pour tolérer les repas du funnel public (forme `{kind, people}` sans
# date). Tarif €/pers (`Pricing::Catalog::MEAL_PER_PERSON_CENTS`).
class MealOrder < ApplicationRecord
  belongs_to :stay

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :price_cents, allow_nil: true

  validates :kind, presence: true
  validates :people, numericality: { only_integer: true, greater_than: 0 }

  # Libellé lisible du type de repas (fallback sur la clé humanisée).
  MEAL_LABELS = {
    "repas_vege_midi"  => "Repas végé (midi)",
    "buffet"           => "Buffet pain-fromages"
  }.freeze

  def label
    MEAL_LABELS[kind.to_s] || kind.to_s.tr("_", " ").capitalize
  end
end
