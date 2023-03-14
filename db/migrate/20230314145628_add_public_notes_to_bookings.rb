class AddPublicNotesToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :public_notes, :text
  end
end
