# == Schema Information
#
# Table name: cycles
#
#  id         :bigint           not null, primary key
#  closed_at  :datetime
#  deleted_at :datetime
#  end_date   :date             not null
#  name       :string           not null
#  start_date :date             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_cycles_on_start_date_and_end_date  (start_date,end_date)
#
class Cycle < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :cycle_actions

  validates :name, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date

  scope :covering_date, ->(date) { where("start_date <= ? AND end_date >= ?", date, date) }
  scope :overlapping, ->(range_start, range_end) { where("start_date <= ? AND end_date >= ?", range_end, range_start) }
  scope :chronological, -> { order(start_date: :desc) }
  scope :open, -> { where(closed_at: nil) }
  scope :closed, -> { where.not(closed_at: nil) }

  # Le cycle sur lequel le collectif travaille : celui qui couvre `date` ;
  # sinon le dernier cycle passé tant qu'il n'est pas clos (on y travaille
  # encore) ; une fois clos, le prochain à venir ; sinon le dernier passé.
  def self.reference_for(date = Date.current)
    covering = covering_date(date).first
    return covering if covering
    last_past = where("end_date < ?", date).order(end_date: :desc).first
    return last_past if last_past&.open?
    where("start_date > ?", date).order(:start_date).first || last_past
  end

  def next_cycle
    Cycle.where("start_date > ?", end_date).order(:start_date).first
  end

  def previous_cycle
    Cycle.where("end_date < ?", start_date).order(end_date: :desc).first
  end

  def closed?
    closed_at.present?
  end

  def open?
    !closed?
  end

  def current?(date = Date.current)
    date.between?(start_date, end_date)
  end

  def past?(date = Date.current)
    end_date < date
  end

  def future?(date = Date.current)
    start_date > date
  end

  def weeks_total
    ((end_date - start_date).to_i + 1) / 7.0
  end

  private

  def end_date_after_start_date
    return unless start_date && end_date
    errors.add(:end_date, "doit être après la date de début") if end_date < start_date
  end
end
