# Produit de buffet PARAMÉTRÉ (epic #219, phase 6) : ce que Michael sait par
# cœur — quel produit, en quelle quantité par personne, pour quels types de
# prestation — et que `Kitchen::ShoppingList` lit pour calculer une liste de
# courses. Ce sont des réglages (comme les tarifs) : suppression réelle,
# jamais de soft-deletion.
# == Schema Information
#
# Table name: kitchen_products
#
#  id                  :bigint           not null, primary key
#  active              :boolean          default(TRUE), not null
#  kinds               :jsonb            not null
#  name                :string           not null
#  note                :string
#  position            :integer
#  quantity_per_person :decimal(8, 2)    not null
#  unit                :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_kitchen_products_on_kinds  (kinds) USING gin
#
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

  # Libellé long, pour les formulaires : « Grammes (g) ».
  def unit_label = UNIT_LABELS[unit.to_s]

  # Libellé court, pour les listes : « 80 g », « 0,5 pièce ». Le zéro décimal
  # inutile est retiré — une quantité par personne se lit d'un coup d'œil.
  def quantity_label
    value = quantity_per_person
    number = value == value.to_i ? value.to_i.to_s : format("%g", value).tr(".", ",")
    unit == "piece" ? "#{number} #{'pièce'.pluralize(value.to_i > 1 ? 2 : 1)}" : "#{number} #{unit}"
  end

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
