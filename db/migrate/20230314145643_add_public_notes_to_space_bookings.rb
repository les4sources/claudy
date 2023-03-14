class AddPublicNotesToSpaceBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :space_bookings, :public_notes, :text
  end
end
