# Un frais fixe d'un événement (epic #245, décision 3) : la location d'un
# espace, ou toute autre dépense. Il se déduit de la recette AVANT le partage
# avec les organisateurs.
#
# `source` pointe la pièce quand elle existe — une `SpaceBooking` aujourd'hui,
# une facture d'achat ou une note de frais quand ces modèles arriveront. Le lien
# évite qu'un même frais soit compté deux fois.
class EventCost < ApplicationRecord
  KINDS = %w[space other].freeze
  KIND_LABELS = { "space" => "Espace", "other" => "Autre" }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :event
  belongs_to :source, polymorphic: true, optional: true

  validates :label, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:created_at, :id) }

  def kind_label = KIND_LABELS.fetch(kind, kind)
end
