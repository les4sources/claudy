class AddPlatformToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :platform, :string
  end
end
