class AddGroupNameToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :group_name, :string
  end
end
