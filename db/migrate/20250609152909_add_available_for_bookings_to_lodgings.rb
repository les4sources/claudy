class AddAvailableForBookingsToLodgings < ActiveRecord::Migration[7.0]
  def change
    add_column :lodgings, :available_for_bookings, :boolean
  end
end
