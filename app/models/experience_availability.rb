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

  validates :available_on, :starts_at, presence: true
  validates :duration_minutes, numericality: { greater_than: 0 }, allow_nil: true
  validates :max_participants, numericality: { greater_than: 0 }, allow_nil: true

  scope :upcoming, -> { where("available_on >= ?", Date.today).order(:available_on, :starts_at) }
  scope :for_date_range, ->(from, to) { where(available_on: from..to) }

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
end
