# Produit de buffet PARAMÉTRÉ (epic #219, phase 6) : ce que Michael sait par
# cœur — quel produit, en quelle quantité par personne, pour quels types de
# prestation — et que `Kitchen::ShoppingList` lit pour calculer une liste de
# courses. Ce sont des réglages (comme les tarifs) : suppression réelle,
# jamais de soft-deletion.
class KitchenProduct < ApplicationRecord
  UNITS = %w[g ml piece].freeze
  UNIT_LABELS = { "g" => "Grammes (g)", "ml" => "Millilitres (ml)", "piece" => "Pièces" }.freeze

  # Sous-ensemble des types de MealOrder concernés par un buffet ou un apéro —
  # les repas de Stéphanie ne passent jamais par une liste de courses, elle
  # fait ses propres courses.
  KINDS = %w[buffet_vege buffet_viande apero].freeze

  before_validation :compact_kinds

  validates :name, presence: true
  validates :unit, presence: true, inclusion: { in: UNITS }
  validates :quantity_per_person, presence: true, numericality: { greater_than: 0 }
  validate :kinds_are_known

  scope :active, -> { where(active: true) }
  scope :for_kind, ->(kind) { where("kinds @> ?::jsonb", [kind.to_s].to_json) }
  scope :ordered, -> { order(Arel.sql("position ASC NULLS LAST"), :name) }

  def unit_label = UNIT_LABELS[unit.to_s]

  def kind_labels
    kinds.map { |kind| MealOrder.label_for(kind) }
  end

  private

  # Un formulaire envoie toujours le champ caché ET la case cochée : décocher
  # tous les types laisse une chaîne vide dans le tableau, sans ce nettoyage.
  def compact_kinds
    self.kinds = Array(kinds).reject(&:blank?)
  end

  def kinds_are_known
    return if Array(kinds).all? { |kind| KINDS.include?(kind) }

    errors.add(:kinds, "doivent faire partie des types connus")
  end
end
