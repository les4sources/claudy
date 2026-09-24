# Notes prises pendant la réunion sur un point de l'ODJ. Rattachées au couple
# (point, rassemblement) et non au point seul : reporter un point le déplace
# vers un autre rassemblement, mais ce qui s'est dit reste là où ça s'est dit.
class AgendaItemNote < ApplicationRecord
  belongs_to :agenda_item
  belongs_to :gathering

  has_paper_trail

  has_rich_text :body

  validates :gathering_id, uniqueness: { scope: :agenda_item_id }
end
