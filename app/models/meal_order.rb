# == Schema Information
#
# Table name: meal_orders
#
#  id          :bigint           not null, primary key
#  stay_id     :bigint           not null
#  kind        :string
#  date        :date
#  people      :integer          default(1), not null
#  price_cents :integer
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
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
