class AddWifiToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :wifi, :boolean, default: false
  end
end
