# == Schema Information
#
# Table name: experience_availabilities
#
#  id                 :bigint           not null, primary key
#  experience_id      :bigint           not null
#  available_on       :date
#  starts_at          :string
#  duration_minutes   :integer
#  max_participants   :integer
#  notes              :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class ExperienceAvailability < ApplicationRecord
  STATUSES = %w[open full].freeze

  belongs_to :experience
  has_many :experience_bookings, dependent: :destroy

  before_validation :default_duration_from_experience

  validates :available_on, :starts_at, presence: true
  validates :duration_minutes, numericality: { greater_than: 0 }, allow_nil: true
  validates :max_participants, numericality: { greater_than: 0 }, allow_nil: true

  # Phase 4 de l'epic #25 : les blocs vivent entre 8h et 22h et ne se
  # chevauchent jamais pour une même activité.
  validate :within_opening_hours
  validate :no_overlap_with_siblings

  scope :upcoming, -> { where("available_on >= ?", Date.today).order(:available_on, :starts_at) }
  scope :for_date_range, ->(from, to) { where(available_on: from..to) }

  # Créneaux sur lesquels un utilisateur a le droit d'agir (créer une activité
  # sur un séjour — epic #55, Phase 6). MÊME mécanisme de cloisonnement que
  # `ExperienceBooking.for_user` : tout pour un admin global, seulement les
  # créneaux de SES propres `Experience` pour un porteur. Centralisé ici pour
  # qu'un porteur qui cible le créneau d'un autre porteur obtienne un `nil`
  # (jamais une création réussie hors périmètre).
  def self.for_user(user)
    return all if user.nil? || user.global_admin?

    joins(:experience).where(experiences: { human_id: user.human_id })
  end

  def ends_at
    return nil unless starts_at.present? && effective_duration.positive?
    h, m = starts_at.split(":").map(&:to_i)
    total = h * 60 + m + effective_duration
    "%02d:%02d" % [total / 60, total % 60]
  end

  def effective_duration
    duration_minutes || 0
  end

  def effective_max_participants
    max_participants || experience.max_participants
  end

  def booked_participants
    experience_bookings.where.not(status: "cancelled").sum(:participants)
  end

  def available_spots
    cap = effective_max_participants
    return nil if cap.nil?
    [cap - booked_participants, 0].max
  end

  def full?
    spots = available_spots
    spots&.zero?
  end

  def label
    "#{experience.name} — #{available_on.strftime('%-d/%m')} à #{starts_at}"
  end

  # Bornes du bloc en minutes depuis minuit — nil si l'heure de début est
  # illisible (la validation de présence/format s'en charge par ailleurs).
  def starts_at_minutes
    Experiences::WeekCalendar.parse_time(starts_at)
  end

  def ends_at_minutes
    start = starts_at_minutes
    return nil if start.nil?

    start + effective_duration
  end

  private

  # Le bloc prend la durée de l'activité quand rien n'est précisé : c'est elle
  # qui pilote la taille des créneaux du calendrier hebdo.
  def default_duration_from_experience
    return if duration_minutes.present?
    return if experience.nil?

    self.duration_minutes = experience.block_duration_minutes
  end

  def within_opening_hours
    start = starts_at_minutes
    return if start.nil?

    finish = ends_at_minutes
    return if finish.nil?

    if start < Experiences::WeekCalendar::DAY_START_MINUTES || finish > Experiences::WeekCalendar::DAY_END_MINUTES
      errors.add(:starts_at, "doit tenir entre 8h et 22h")
    end
  end

  def no_overlap_with_siblings
    start = starts_at_minutes
    finish = ends_at_minutes
    return if start.nil? || finish.nil? || experience.nil? || available_on.nil?

    siblings = experience.experience_availabilities.where(available_on: available_on)
    siblings = siblings.where.not(id: id) if persisted?

    overlapping = siblings.any? do |sibling|
      sibling_start = sibling.starts_at_minutes
      sibling_end = sibling.ends_at_minutes
      next false if sibling_start.nil? || sibling_end.nil?

      start < sibling_end && sibling_start < finish
    end

    errors.add(:starts_at, "chevauche une disponibilité déjà posée") if overlapping
  end
end
