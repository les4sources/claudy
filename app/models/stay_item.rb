# == Schema Information
#
# Table name: stay_items
#
#  id            :bigint           not null, primary key
#  stay_id       :bigint           not null
#  bookable_type :string           not null
#  bookable_id   :bigint           not null
#  deleted_at    :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class StayItem < ApplicationRecord
  belongs_to :stay
  # Polymorphic, extensible: Booking + SpaceBooking today; ActivityBooking,
  # EventBooking, MealOrder, … later without a schema change.
  belongs_to :bookable, polymorphic: true

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :bookable_type, inclusion: { in: %w[Booking SpaceBooking] }
  validates :bookable_id, uniqueness: { scope: [:stay_id, :bookable_type] }
end
