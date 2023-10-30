# == Schema Information
#
# Table name: space_reservations
#
#  id               :bigint           not null, primary key
#  space_booking_id :bigint           not null
#  space_id         :bigint           not null
#  date             :date
#  duration         :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  deleted_at       :datetime
#
require 'rails_helper'

RSpec.describe SpaceReservation, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
