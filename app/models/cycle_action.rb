# == Schema Information
#
# Table name: cycle_actions
#
#  id                    :bigint           not null, primary key
#  archived_at           :datetime
#  category              :integer          default(0), not null
#  completed             :boolean          default(FALSE)
#  completed_occurrences :integer          default(0), not null
#  deferral_count        :integer          default(0), not null
#  deleted_at            :datetime
#  economic              :boolean          default(FALSE), not null
#  hours                 :decimal(5, 2)
#  label                 :string           not null
#  occurrences           :integer          default(1), not null
#  outcome               :integer
#  position              :integer          default(0), not null
#  unit_hours            :decimal(5, 2)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  cycle_id              :bigint
#  deferred_from_id      :bigint
#  delegate_to_human_id  :bigint
#  human_id              :bigint           not null
#
# Indexes
#
#  index_cycle_actions_on_category                            (category)
#  index_cycle_actions_on_completed                           (completed)
#  index_cycle_actions_on_cycle_id                            (cycle_id)
#  index_cycle_actions_on_cycle_id_and_human_id               (cycle_id,human_id)
#  index_cycle_actions_on_deferred_from_id                    (deferred_from_id)
#  index_cycle_actions_on_delegate_to_human_id                (delegate_to_human_id)
#  index_cycle_actions_on_economic                            (economic)
#  index_cycle_actions_on_human_id                            (human_id)
#  index_cycle_actions_on_human_id_and_archived_at            (human_id,archived_at)
#  index_cycle_actions_on_human_id_and_category_and_position  (human_id,category,position)
#
# Foreign Keys
#
#  fk_rails_...  (cycle_id => cycles.id)
#  fk_rails_...  (deferred_from_id => cycle_actions.id)
#  fk_rails_...  (delegate_to_human_id => humans.id)
#  fk_rails_...  (human_id => humans.id)
#
class CycleAction < ApplicationRecord
  belongs_to :human
  belongs_to :cycle
  belongs_to :delegate_to_human, class_name: "Human", optional: true
  # Quand une action est passée au cycle suivant, l'origine reste dans son
  # cycle avec l'issue « reportée » et la copie pointe vers elle.
  belongs_to :deferred_from, class_name: "CycleAction", optional: true
  has_one :deferred_to, class_name: "CycleAction", foreign_key: :deferred_from_id

  has_paper_trail
  has_soft_deletion default_scope: true

  enum :category, {
    rituelle: 0,
    ponctuelle: 1,
    reportee: 2,
    deleguee: 3,
    demandee: 4,
    invitee: 5
  }

  # Issue de l'action dans son cycle. `nil` tant qu'elle est en cours.
  enum :outcome, {
    done: 0,
    deferred: 1,
    dropped: 2
  }, prefix: true

  validates :label, presence: true
  validates :category, presence: true
  # OCCURRENCES (issue #338) : `unit_hours` est la durée d'UNE fois,
  # `occurrences` combien de fois dans le cycle. `hours` reste le total engagé —
  # c'est lui que tout le monde additionne, son sens ne change pas.
  validates :occurrences, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :completed_occurrences, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :completed_occurrences_within_occurrences

  scope :active, -> { where(completed: false) }
  scope :for_human, ->(human) { where(human: human) }
  scope :for_cycle, ->(cycle) { where(cycle: cycle) }
  scope :ordered, -> { order(:completed, :position, :created_at) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :not_archived, -> { where(archived_at: nil) }
  # Encore en jeu dans son cycle : ni archivée, ni déjà tranchée.
  scope :live, -> { not_archived.where(outcome: nil) }
  scope :settled, -> { where.not(outcome: nil) }
  scope :engaged, -> { where.not(category: :reportee) }
  # ACTIVITÉ ÉCONOMIQUE (epic #330, phase 1) : une prestation qui rapporte au
  # lieu de consommer le temps collectif. Elle reste visible et comptée, mais à
  # part — elle ne mange pas le budget d'heures du cycle.
  #
  # L'exclusion ne vaut QUE pour le bloc de charge de la page membre
  # (décision 3) : le bilan de clôture et le récap membre continuent de compter
  # ces heures comme avant.
  scope :economic, -> { where(economic: true) }
  scope :non_economic, -> { where(economic: false) }

  before_validation :normalise_occurrences
  before_create :set_default_position

  def archived?
    archived_at.present?
  end

  def live?
    !archived? && outcome.nil?
  end

  # Archiver = sortir l'action du cycle sans la passer au suivant. L'issue
  # découle de la case : cochée → faite, sinon → abandonnée.
  def archive!
    update!(archived_at: Time.current, outcome: completed? ? :done : :dropped)
  end

  def unarchive!
    update!(archived_at: nil, outcome: nil)
  end

  def deferred_before?
    deferral_count.to_i > 0
  end

  # Répétée dans le cycle : la ligne montre alors le détail `3 × 11h`.
  def multiple?
    occurrences.to_i > 1
  end

  # Les heures réellement faites. Pour une action « une fois » c'est `hours` si
  # cochée et 0 sinon — exactement comme avant.
  def completed_hours
    (unit_hours || 0) * completed_occurrences.to_i
  end

  # Ce qu'il reste à faire dans le cycle courant.
  def remaining_occurrences
    [occurrences.to_i - completed_occurrences.to_i, 0].max
  end

  # Ce que la copie emporte dans le cycle suivant : le reste à faire. Une action
  # entièrement faite (une rituelle qu'on relance) repart au contraire sur son
  # nombre de fois complet — sinon un batchcooking rituel 3 × se réduirait à 1 ×
  # à chaque clôture.
  def carry_over_occurrences
    return occurrences.to_i if completed?
    [remaining_occurrences, 1].max
  end

  # HEURES RÉELLES (epic #330, phase 2) : `hours` reste l'ESTIMÉ engagé — c'est
  # lui que le bilan et le budget du cycle additionnent (décision 3). Le réel
  # vit à côté, alimenté au clic par `add_actual_hour` / `remove_actual_hour`,
  # et ne descend jamais sous zéro.
  ACTUAL_HOUR_STEP = 1.0

  def actual_hours_recorded?
    actual_hours.to_f.positive?
  end

  def add_actual_hour!(step = ACTUAL_HOUR_STEP)
    update!(actual_hours: actual_hours.to_f + step)
  end

  def remove_actual_hour!(step = ACTUAL_HOUR_STEP)
    update!(actual_hours: [actual_hours.to_f - step, 0].max)
  end

  private

  # `hours` est dérivé de `unit_hours × occurrences` dès qu'on a une durée
  # unitaire. Une saisie ancienne (ou l'API) qui ne connaît que `hours` reste
  # acceptée : on en dérive `unit_hours`. `completed` devient la conséquence des
  # occurrences cochées, ce qui laisse intact tout le code qui lit `completed?`.
  def normalise_occurrences
    self.occurrences = 1 if occurrences.blank?
    self.completed_occurrences = 0 if completed_occurrences.blank?

    # Chemin historique : `toggle_completed`, `settle`, l'API — tout ce qui
    # bascule la case unique sans connaître les occurrences. On reporte la
    # bascule sur le compteur, puis la case se redéduit de lui.
    if completed_changed? && !completed_occurrences_changed?
      self.completed_occurrences = completed? ? occurrences.to_i : 0
    end

    # Réduire le nombre de fois ramène les occurrences faites dans les clous
    # (édition). Une saisie directe hors bornes, elle, est refusée en validation.
    if occurrences_changed? && completed_occurrences.to_i > occurrences.to_i
      self.completed_occurrences = occurrences
    end

    # Qui pilote le total ? La durée unitaire, dès qu'elle bouge ou que le
    # nombre de fois bouge. Sinon un `hours` posé directement (API, ancienne
    # saisie) fait foi et la durée unitaire s'en déduit. Une sauvegarde qui ne
    # touche à aucun des trois (cocher, archiver…) ne recalcule rien : le total
    # d'une action existante ne bouge jamais tout seul.
    if unit_hours.present? && (unit_hours_changed? || occurrences_changed? || hours.blank?)
      self.hours = (unit_hours * occurrences.to_i).round(2)
    elsif hours.present? && (unit_hours.blank? || hours_changed?)
      self.unit_hours = (hours / occurrences.to_i).round(2)
    end

    self.completed = completed_occurrences.to_i >= occurrences.to_i
  end

  def completed_occurrences_within_occurrences
    return if completed_occurrences.blank? || occurrences.blank?
    return if completed_occurrences.to_i.between?(0, occurrences.to_i)
    errors.add(:completed_occurrences, "doit être compris entre 0 et #{occurrences}")
  end

  def set_default_position
    return if position.to_i > 0
    max = CycleAction.where(human_id: human_id, category: category, cycle_id: cycle_id).maximum(:position) || -1
    self.position = max + 1
  end
end
