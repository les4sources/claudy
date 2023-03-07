class SpaceReservation < ApplicationRecord
  belongs_to :space_booking
  belongs_to :event, optional: true
  belongs_to :space

  def start_time
    date.to_time
  end
end
