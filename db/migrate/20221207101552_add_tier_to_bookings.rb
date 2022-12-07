class AddTierToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :tier, :string
  end
end
