class AddInvoiceStatusToStay < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :invoice_status, :string
  end
end
