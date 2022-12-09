class AddOptionDiscgolfToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :option_discgolf, :boolean
  end
end
