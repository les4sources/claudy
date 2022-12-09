class AddShownPriceToBookings < ActiveRecord::Migration[7.0]
  def change
    add_monetize :bookings, :shown_price, currency: { present: false }
  end
end
