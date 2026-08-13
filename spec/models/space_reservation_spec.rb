# == Schema Information
#
# Table name: space_reservations
#
#  id               :bigint           not null, primary key
#  date             :date
#  deleted_at       :datetime
#  duration         :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  space_booking_id :bigint           not null
#  space_id         :bigint           not null
#
# Indexes
#
#  index_space_reservations_on_space_booking_id  (space_booking_id)
#  index_space_reservations_on_space_id          (space_id)
#
# Foreign Keys
#
#  fk_rails_...  (space_booking_id => space_bookings.id)
#  fk_rails_...  (space_id => spaces.id)
#
require 'rails_helper'

RSpec.describe SpaceReservation, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
