# Une note datée de la carte du domaine (epic #348, phase 7) : « 12 mars :
# bourgeons gelés ». Elle porte sur une plante — ou sur n'importe quel objet de
# la carte. La fiche les liste de la plus récente à la plus ancienne.
class MapNote < ApplicationRecord
  # Liste FERMÉE : le type polymorphe ne vient jamais d'un paramètre, et quand
  # il est lu (`subject`, `with_live_subject`), c'est forcément l'un de ceux-ci.
  SUBJECT_TYPES = %w[MapFeature Plant].freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :subject, polymorphic: true
  belongs_to :author, class_name: "User", optional: true

  # Le défaut de la base (`CURRENT_DATE`) n'est pas visible d'un objet Ruby
  # neuf : on le pose ici, pour que la fiche l'affiche avant l'enregistrement.
  after_initialize { self.noted_on ||= Date.current if new_record? }
  before_validation { self.body = body.to_s.strip.presence }

  validates :body, presence: true
  validates :noted_on, presence: true
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }

  scope :recent_first, -> { order(noted_on: :desc, created_at: :desc, id: :desc) }

  # Les notes dont le porteur est VIVANT (cf. `MapTask.with_live_subject`).
  def self.with_live_subject
    SUBJECT_TYPES.map { |type| where(subject_type: type, subject_id: type.constantize.select(:id)) }.reduce(:or)
  end
end
