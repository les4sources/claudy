# == Schema Information
#
# Table name: stay_items
#
#  id            :bigint           not null, primary key
#  bookable_type :string           not null
#  deleted_at    :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bookable_id   :bigint           not null
#  stay_id       :bigint           not null
#
# Indexes
#
#  index_stay_items_on_bookable_type_and_bookable_id  (bookable_type,bookable_id)
#  index_stay_items_on_stay_and_bookable_unique_live  (stay_id,bookable_type,bookable_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_stay_items_on_stay_id                        (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (stay_id => stays.id)
#
class StayItem < ApplicationRecord
  belongs_to :stay
  # Polymorphic, extensible: Booking + SpaceBooking + CampingBooking + VanBooking
  # + HamacBooking (issue #138) aujourd'hui. Les repas (MealOrder) n'occupent PAS le calendrier
  # → rattachés en direct sur Stay, pas via StayItem.
  belongs_to :bookable, polymorphic: true

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :bookable_type, inclusion: { in: %w[Booking SpaceBooking CampingBooking VanBooking HamacBooking] }
  validates :bookable_id, uniqueness: { scope: [:stay_id, :bookable_type] }
end
