class AddExtraFieldsToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :invoice_status, :boolean
    add_column :bookings, :contract_status, :string
    add_column :bookings, :estimated_arrival, :string
  end
end
