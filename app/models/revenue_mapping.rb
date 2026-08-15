# À quel compte de recette rattacher chaque catégorie d'un devis de séjour.
#
# Le compte général est mécanique — une nuitée est un produit d'hébergement. Le
# PÔLE ne l'est pas : savoir lequel porte l'hébergement est une décision du
# collectif, pas une évidence technique. La colonne reste donc vide tant que
# personne ne l'a tranchée, et une recette sans pôle apparaît comme non affectée
# plutôt que rangée au hasard.
class RevenueMapping < ApplicationRecord
  CATEGORIES = %w[lodging spaces camping van meals terrace hamac experiences].freeze
  CATEGORY_LABELS = {
    "lodging" => "Hébergement",
    "spaces" => "Salles",
    "camping" => "Camping",
    "van" => "Van",
    "meals" => "Repas",
    "terrace" => "Terrasse",
    "hamac" => "Hamacs",
    "experiences" => "Activités"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :general_account
  belongs_to :team, optional: true

  validates :category, presence: true, uniqueness: true, inclusion: { in: CATEGORIES }

  scope :ordered, -> { order(:category) }

  def category_label = CATEGORY_LABELS.fetch(category, category)
end
