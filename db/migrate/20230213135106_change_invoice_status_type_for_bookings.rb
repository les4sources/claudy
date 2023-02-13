class ChangeInvoiceStatusTypeForBookings < ActiveRecord::Migration[7.0]
  def change
    change_column :bookings, :invoice_status, :string
  end
end
