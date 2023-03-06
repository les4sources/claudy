class AddBabiesToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :babies, :integer, default: 0
  end
end
