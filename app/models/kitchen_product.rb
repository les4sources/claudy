# Produit de buffet PARAMÉTRÉ (epic #219, phase 6) : ce que Michael sait par
# cœur — quel produit, en quelle quantité par personne, pour quels types de
# prestation — et que `Kitchen::ShoppingList` lit pour calculer une liste de
# courses. Ce sont des réglages (comme les tarifs) : suppression réelle,
# jamais de soft-deletion.
#
# `quantities` porte une quantité PAR TYPE : `{"buffet_vege" => "80",
# "buffet_viande" => "50"}`. La présence de la clé dit que le produit concerne
# ce type — un seul « Fromages » sert les deux buffets, chacun à sa dose.
# == Schema Information
#
# Table name: kitchen_products
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  name       :string           not null
#  note       :string
#  position   :integer
#  quantities :jsonb            not null
#  unit       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_kitchen_products_on_quantities  (quantities) USING gin
#
class KitchenProduct < ApplicationRecord
  UNITS = %w[g ml piece].freeze
  UNIT_LABELS = { "g" => "Grammes (g)", "ml" => "Millilitres (ml)", "piece" => "Pièces" }.freeze

  # Sous-ensemble des types de MealOrder concernés par un buffet ou un apéro —
  # les repas de Stéphanie ne passent jamais par une liste de courses, elle
  # fait ses propres courses.
  KINDS = %w[buffet_vege buffet_viande apero].freeze

  before_validation :normalize_quantities

  validates :name, presence: true
  validates :unit, presence: true, inclusion: { in: UNITS }
  validate :quantities_are_usable

  scope :active, -> { where(active: true) }
  # L'opérateur jsonb `?` (« cette clé existe-t-elle ? ») est celui que sert
  # l'index GIN. Il impose le paramètre NOMMÉ : avec un `?` positionnel, Arel
  # compterait l'opérateur lui-même comme une variable de liaison.
  scope :for_kind, ->(kind) { where("quantities ? :kind", kind: kind.to_s) }
  scope :ordered, -> { order(Arel.sql("position ASC NULLS LAST"), :name) }

  # Libellé long, pour les formulaires : « Grammes (g) ».
  def unit_label = UNIT_LABELS[unit.to_s]

  # Quantité par personne pour un type — nil si le produit ne le concerne pas.
  def quantity_for(kind) = quantities[kind.to_s]&.to_d

  # Les types concernés, dans l'ordre canonique et non dans celui du jsonb.
  def kinds = KINDS & quantities.keys

  def kind_labels = kinds.map { |kind| MealOrder.label_for(kind) }

  # Libellé court, pour les listes : « 80 g », « 0,5 pièce ». Le zéro décimal
  # inutile est retiré — une quantité par personne se lit d'un coup d'œil.
  def quantity_label(kind)
    value = quantity_for(kind)
    return if value.nil?

    number = value == value.to_i ? value.to_i.to_s : format("%g", value).tr(".", ",")
    unit == "piece" ? "#{number} #{'pièce'.pluralize(value.to_i > 1 ? 2 : 1)}" : "#{number} #{unit}"
  end

  private

  # Le formulaire envoie les trois types, dont ceux laissés vides : un champ
  # vide veut dire « ce produit ne concerne pas ce type ». La virgule décimale
  # est acceptée — on tape « 0,5 » sur un clavier belge.
  def normalize_quantities
    source = quantities.respond_to?(:to_unsafe_h) ? quantities.to_unsafe_h : quantities
    self.quantities = Hash(source).slice(*KINDS)
                                  .transform_values { |value| value.to_s.strip.tr(",", ".") }
                                  .reject { |_, value| value.blank? }
  end

  # Le message est posé sur `:base` : il porte sur les trois champs à la fois,
  # et le nom technique de la colonne n'a rien à faire sous les yeux de Michael.
  def quantities_are_usable
    if quantities.blank?
      errors.add(:base, "Il faut une quantité pour au moins un type de prestation")
      return
    end

    return if quantities.each_value.all? { |value| Float(value, exception: false).to_f.positive? }

    errors.add(:base, "Les quantités doivent être des nombres supérieurs à zéro")
  end
end
