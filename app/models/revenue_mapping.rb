# À quel compte de recette rattacher chaque catégorie d'un devis de séjour.
#
# Le compte général est mécanique — une nuitée est un produit d'hébergement. Le
# PÔLE ne l'est pas : savoir lequel porte l'hébergement est une décision du
# collectif, pas une évidence technique. La colonne reste donc vide tant que
# personne ne l'a tranchée, et une recette sans pôle apparaît comme non affectée
# plutôt que rangée au hasard.
#
# Tranché depuis (Michael, 2026-10-19) : un séjour relève du pôle Accueil, et
# `Finance::VentilateStay` y range toutes ses lignes. Ce pôle-ci n'est plus
# qu'un repli, si aucun pôle Accueil n'existe.
# == Schema Information
#
# Table name: revenue_mappings
#
#  id                 :bigint           not null, primary key
#  category           :string           not null
#  deleted_at         :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint           not null
#  team_id            :bigint
#
# Indexes
#
#  index_revenue_mappings_on_category            (category) UNIQUE
#  index_revenue_mappings_on_deleted_at          (deleted_at)
#  index_revenue_mappings_on_general_account_id  (general_account_id)
#  index_revenue_mappings_on_team_id             (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (team_id => teams.id)
#
class RevenueMapping < ApplicationRecord
  CATEGORIES = %w[lodging spaces camping van meals terrace hamac experiences services].freeze
  CATEGORY_LABELS = {
    "lodging" => "Hébergement",
    "spaces" => "Salles",
    "camping" => "Camping",
    "van" => "Van",
    "meals" => "Repas",
    "terrace" => "Terrasse",
    "hamac" => "Hamacs",
    "experiences" => "Activités",
    "services" => "Services annexes"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :general_account
  belongs_to :team, optional: true

  validates :category, presence: true, uniqueness: true, inclusion: { in: CATEGORIES }

  scope :ordered, -> { order(:category) }

  def category_label = CATEGORY_LABELS.fetch(category, category)
end
