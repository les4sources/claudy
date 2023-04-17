class AddAdvanceAmountToSpaceBookings < ActiveRecord::Migration[7.0]
  def change
    add_monetize :space_bookings, :advance_amount, amount: { null: true, default: nil }, currency: { present: false }
  end
end
