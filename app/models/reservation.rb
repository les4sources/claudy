class Reservation < ApplicationRecord
  belongs_to :booking
  belongs_to :room

  has_paper_trail

  def start_time
    date.to_time
  end
end
