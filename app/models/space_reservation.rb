class SpaceReservation < ApplicationRecord
  belongs_to :space_booking
  belongs_to :space

  has_paper_trail
  has_soft_deletion default_scope: true

  def start_time
    date.to_time
  end
end
