# La dotation d'une immobilisation pour un exercice : la pièce de l'écriture
# 630 / 2x9. Une seule par bien et par exercice (index unique) ; une dotation
# fausse se contre-passe et se refait, elle ne se retouche pas.
class FixedAssetDepreciation < ApplicationRecord
  has_paper_trail

  belongs_to :fixed_asset
  belongs_to :fiscal_year
  has_one :journal_entry, as: :source, dependent: :restrict_with_error

  monetize :amount_cents

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
end
