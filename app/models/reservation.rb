class Reservation < ApplicationRecord
  belongs_to :booking
  belongs_to :room

  def start_time
    date.to_time
  end
end
