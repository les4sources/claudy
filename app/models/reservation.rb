# == Schema Information
#
# Table name: reservations
#
#  id         :bigint           not null, primary key
#  booking_id :bigint           not null
#  room_id    :bigint           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  date       :date
#  deleted_at :datetime
#
class Reservation < ApplicationRecord
  belongs_to :booking
  belongs_to :room

  has_paper_trail
  # The `deleted_at` column was added alongside every other soft-deletable model
  # (migration 20230706080125) but the behaviour was never wired up here. Without
  # it, a reservation whose `deleted_at` is set (e.g. soft-deleted via the agent
  # API) stays visible in `room.reservations` and keeps blocking availability —
  # producing a false "Cet hébergement n'est pas disponible à cette date."
  has_soft_deletion default_scope: true

  def start_time
    date.to_time
  end
end
