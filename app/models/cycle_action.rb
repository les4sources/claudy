# == Schema Information
#
# Table name: cycle_actions
#
#  id                   :bigint           not null, primary key
#  archived_at          :datetime
#  category             :integer          default(0), not null
#  completed            :boolean          default(FALSE)
#  deferral_count       :integer          default(0), not null
#  deleted_at           :datetime
#  economic             :boolean          default(FALSE), not null
#  hours                :decimal(5, 2)
#  label                :string           not null
#  outcome              :integer
#  position             :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  cycle_id             :bigint
#  deferred_from_id     :bigint
#  delegate_to_human_id :bigint
#  human_id             :bigint           not null
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

  def set_default_position
    return if position.to_i > 0
    max = CycleAction.where(human_id: human_id, category: category, cycle_id: cycle_id).maximum(:position) || -1
    self.position = max + 1
  end
end
