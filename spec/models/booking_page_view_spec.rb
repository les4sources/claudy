require "rails_helper"

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
