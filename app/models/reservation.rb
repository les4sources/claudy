class Reservation < ApplicationRecord
  belongs_to :booking
  belongs_to :room

  has_paper_trail
  has_soft_deletion default_scope: true

  def start_time
    date.to_time
  end
end
