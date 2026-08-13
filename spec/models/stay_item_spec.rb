require "rails_helper"

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
RSpec.describe StayItem, type: :model do
  let(:customer) { Customer.create!(email: "stayitem@example.com", customer_type: "individual") }
  let(:stay) { Stay.create!(customer: customer) }
  let(:booking) do
    Booking.create!(firstname: "Item", from_date: Date.new(2026, 7, 1), to_date: Date.new(2026, 7, 3),
                    adults: 1, status: "confirmed")
  end
  let(:space_booking) do
    SpaceBooking.create!(firstname: "Salle", from_date: Date.new(2026, 7, 1),
                         to_date: Date.new(2026, 7, 1), status: "confirmed")
  end

  it "accepts a Booking as a polymorphic bookable" do
    item = StayItem.new(stay: stay, bookable: booking)
    expect(item).to be_valid
  end

  it "accepts a SpaceBooking as a polymorphic bookable" do
    item = StayItem.new(stay: stay, bookable: space_booking)
    expect(item).to be_valid
  end

  it "rejects an unsupported bookable_type" do
    item = StayItem.new(stay: stay, bookable_type: "Lodging", bookable_id: 1)
    expect(item).not_to be_valid
    expect(item.errors[:bookable_type]).to be_present
  end

  it "forbids attaching the same bookable to a stay twice" do
    StayItem.create!(stay: stay, bookable: booking)
    dup = StayItem.new(stay: stay, bookable: booking)
    expect(dup).not_to be_valid
  end
end
