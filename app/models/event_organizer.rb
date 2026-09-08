# Qui organise un événement, et dans quelle proportion (epic #245, décision 1).
#
# Le poids est un entier ≥ 1 : la part des organisateurs se répartit à son
# prorata. Tous les poids à 1 — le cas courant — donne des parts égales, sans
# que personne ait à saisir de pourcentages.
class EventOrganizer < ApplicationRecord
  has_paper_trail

  belongs_to :event
  belongs_to :human

  validates :weight, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :human_id, uniqueness: { scope: :event_id }
end
