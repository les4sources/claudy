class AddEventIdToSpaceBookings < ActiveRecord::Migration[7.0]
  def change
    remove_reference :space_reservations, :event, foreign_key: true, index: true
    add_reference :space_bookings, :event, null: true, foreign_key: true
  end
end
