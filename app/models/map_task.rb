# Une tâche de gestion de la carte du domaine (epic #348, phase 6) : « Fauche
# des orties », en juin et en septembre, sur la prairie du bas. La consigne de
# gestion (phase 2) reste un texte libre ; la tâche, elle, se range par mois
# pour faire le carnet de l'année (`/map/carnet`).
#
# Aucune notion de « fait » : le carnet dit ce qui revient chaque année, pas ce
# qui a été coché cette année-ci (hors périmètre de la phase).
class MapTask < ApplicationRecord
  # La filière d'une tâche : le terrain (fauche, entretien des accès) ou le
  # nourricier (taille, récolte). Libellés de l'admin, en français.
  SECTORS = { "terrain" => "Terrain", "nourricier" => "Nourricier" }.freeze
  # Ce qui peut porter une tâche, et la filière qu'elle prend par défaut. Liste
  # FERMÉE : le type polymorphe ne vient jamais d'un paramètre, et quand il est
  # lu (`subject`, `with_live_subject`), c'est forcément l'un de ceux-ci. La
  # phase 7 ajoutera `"Plant" => "nourricier"`.
  SUBJECT_TYPES = { "MapFeature" => "terrain" }.freeze
  MONTHS = (1..12).to_a.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :subject, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true

  before_validation :normalize_months, :default_sector
  before_create :append_position

  validates :label, presence: true
  validates :sector, inclusion: { in: SECTORS.keys }
  validates :subject_type, inclusion: { in: SUBJECT_TYPES.keys }
  validate :months_are_calendar_months

  scope :ordered, -> { order(:position, :id) }
  # `@>` plutôt que `= ANY(...)` : c'est l'opérateur que sert l'index GIN.
  scope :in_month, ->(month) { where("map_tasks.months @> ARRAY[?]::integer[]", month.to_i) }
  scope :in_sector, ->(sector) { SECTORS.key?(sector.to_s) ? where(sector: sector.to_s) : all }

  # Les tâches dont le porteur est VIVANT. Un objet soft-deleté garde ses
  # tâches en base (pas de `dependent:` sur un modèle soft-deleté), mais elles
  # n'ont plus rien à faire dans le carnet : sans ce filtre, `task.subject`
  # vaudrait nil (default_scope du porteur) et la page tomberait en 500.
  def self.with_live_subject
    SUBJECT_TYPES.keys.map { |type| where(subject_type: type, subject_id: type.constantize.select(:id)) }.reduce(:or)
  end

  def self.month_name(month) = I18n.t("date.month_names", locale: :fr)[month].to_s.upcase_first

  # L'initiale du mois, pour les douze pastilles.
  def self.month_initial(month) = month_name(month).first

  def sector_label = SECTORS.fetch(sector, sector)

  def subject_name
    subject.respond_to?(:display_name) ? subject.display_name.presence || "Objet sans nom" : subject.to_s
  end

  private

  # Le formulaire envoie des cases à cocher (chaînes, plus une valeur vide
  # toujours présente) : on garde des entiers, uniques et dans l'ordre.
  def normalize_months
    self.months = Array(months).compact.map(&:to_i).uniq.sort
  end

  def default_sector
    self.sector = SUBJECT_TYPES.fetch(subject_type, SECTORS.keys.first) if sector.blank?
  end

  def months_are_calendar_months
    errors.add(:months, "doivent être compris entre 1 et 12") unless months.all? { |month| MONTHS.include?(month) }
  end

  # Une tâche nouvelle va en fin de liste de son porteur.
  def append_position
    self.position ||= (MapTask.unscoped.where(subject_type: subject_type, subject_id: subject_id).maximum(:position) || 0) + 1
  end
end
