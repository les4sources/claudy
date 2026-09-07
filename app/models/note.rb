# == Schema Information
#
# Table name: notes
#
#  id           :bigint           not null, primary key
#  body         :text
#  color        :string
#  date         :date
#  deleted_at   :datetime
#  external_ref :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_notes_on_external_ref_unique_live  (external_ref) UNIQUE WHERE ((deleted_at IS NULL) AND (external_ref IS NOT NULL))
#
class Note < ApplicationRecord
  # `color` sert de TYPE de note — le formulaire étiquette d'ailleurs le champ
  # « Type de note ». Les couples couleur → libellé vivent ici et nulle part
  # ailleurs : le formulaire, l'API et le calendrier lisent tous cette constante.
  TYPES = {
    "yellow" => "Nettoyages",
    "pink" => "Activités",
    "green" => "Locations tente/van",
    "blue" => "Informations/Autres",
    "orange" => "Pizza party"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  # Une couleur vide vaut « pas de type » : sans ça, un `color: ""` envoyé par
  # l'API tomberait sur la validation d'inclusion au lieu de passer par
  # `allow_nil`, et le partial du calendrier rendrait `bg--200`.
  normalizes :color, with: ->(color) { color.presence }
  normalizes :external_ref, with: ->(ref) { ref.presence }

  validates :body, presence: true
  validates :date, presence: true
  validates :color, inclusion: { in: TYPES.keys }, allow_nil: true
  # Le validateur d'unicité de Rails part de `klass.unscoped` : sans cette
  # condition il verrait aussi les notes supprimées en douceur, et refuserait
  # de reposer une note dont la référence a déjà servi puis été effacée.
  validates :external_ref, uniqueness: { conditions: -> { where(deleted_at: nil) } }, allow_nil: true

  scope :matching, ->(term) { where("notes.body ILIKE ?", "%#{term}%") if term.present? }

  # Libellé du type, ou nil si la couleur est vide ou inconnue.
  def type_label
    TYPES[color]
  end
end
