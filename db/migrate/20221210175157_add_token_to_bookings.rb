class AddTokenToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :token, :string
  end
end
