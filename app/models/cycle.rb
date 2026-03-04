class Cycle < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  validates :name, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date

  scope :covering_date, ->(date) { where("start_date <= ? AND end_date >= ?", date, date) }
  scope :overlapping, ->(range_start, range_end) { where("start_date <= ? AND end_date >= ?", range_end, range_start) }
  scope :chronological, -> { order(start_date: :desc) }

  private

  def end_date_after_start_date
    return unless start_date && end_date
    errors.add(:end_date, "doit être après la date de début") if end_date < start_date
  end
end
