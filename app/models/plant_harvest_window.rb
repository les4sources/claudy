# Quand récolter quoi (epic #348, phase 7) : « fruit, en septembre et
# octobre ». Une fenêtre appartient à une espèce (valeur par défaut) ou à une
# plante (surcharge). Une seule fenêtre par partie et par porteur.
class PlantHarvestWindow < ApplicationRecord
  PARTS = {
    "flower" => "Fleur",
    "leaf" => "Feuille",
    "fruit" => "Fruit",
    "root" => "Racine",
    "seed" => "Graine",
    "sap" => "Sève",
    "other" => "Autre"
  }.freeze
  # Liste FERMÉE : le type polymorphe ne vient jamais d'un paramètre.
  OWNER_TYPES = %w[PlantSpecies Plant].freeze
  MONTHS = (1..12).to_a.freeze

  has_paper_trail

  belongs_to :owner, polymorphic: true

  before_validation :normalize_months

  validates :owner_type, inclusion: { in: OWNER_TYPES }
  validates :part, inclusion: { in: PARTS.keys },
                   uniqueness: { scope: %i[owner_type owner_id], message: "a déjà sa fenêtre de récolte" }
  validate :months_are_calendar_months

  # Les parties dans l'ordre de `PARTS` (fleur, feuille, fruit…), la grille de
  # la fiche. Les clés sont des constantes : pas d'injection possible.
  scope :ordered, lambda {
    order(Arel.sql("array_position(ARRAY[#{PARTS.keys.map { |part| "'#{part}'" }.join(',')}]::varchar[], " \
                   "plant_harvest_windows.part::varchar)"), :id)
  }
  # `@>` plutôt que `= ANY(...)` : c'est l'opérateur que sert l'index GIN.
  scope :in_month, ->(month) { where("plant_harvest_windows.months @> ARRAY[?]::integer[]", month.to_i) }
  scope :for_part, ->(part) { PARTS.key?(part.to_s) ? where(part: part.to_s) : all }

  def self.part_label(part) = PARTS.fetch(part.to_s, part.to_s)

  def part_label = self.class.part_label(part)

  def includes_month?(month) = months.include?(month.to_i)

  # « sept., oct. »
  def months_label = months.map { |month| MapTask.month_abbr(month) }.join(", ")

  private

  # Cases à cocher du formulaire (chaînes, valeur vide toujours présente) : on
  # garde des entiers, uniques et dans l'ordre.
  def normalize_months
    self.months = Array(months).compact_blank.map(&:to_i).uniq.sort
  end

  # Une fenêtre sans mois ne dit rien : pour « ne plus récolter les fleurs »,
  # on supprime la fenêtre.
  def months_are_calendar_months
    return errors.add(:months, "doivent compter au moins un mois") if months.empty?

    errors.add(:months, "doivent être compris entre 1 et 12") unless months.all? { |month| MONTHS.include?(month) }
  end
end
