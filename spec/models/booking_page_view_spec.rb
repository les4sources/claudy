require "rails_helper"

# == Schema Information
#
# Table name: booking_page_views
#
#  id         :bigint           not null, primary key
#  ip_address :string
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  booking_id :bigint           not null
#
# Indexes
#
#  index_booking_page_views_on_booking_id  (booking_id)
#
# Foreign Keys
#
#  fk_rails_...  (booking_id => bookings.id)
#
RSpec.describe BookingPageView, type: :model do
  let(:booking) do
    Booking.create!(firstname: "Test", lastname: "Client", from_date: Date.today,
                    to_date: Date.today + 2, adults: 2, token: "tok-model")
  end

  it "appartient à une réservation" do
    view = booking.page_views.create!(ip_address: "1.2.3.4", user_agent: "RSpec")
    expect(view.booking).to eq(booking)
    expect(booking.page_views).to include(view)
  end

  it "est supprimée avec sa réservation (dependent: :destroy)" do
    booking.page_views.create!
    expect { booking.destroy }.to change(BookingPageView, :count).by(-1)
  end
end
