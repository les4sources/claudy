class AddInvoiceAndPaymentStatusToPaymentRequests < ActiveRecord::Migration[7.0]
  def change
    add_column :payment_requests, :invoice_status, :string
    add_column :payment_requests, :payment_status, :string
  end
end
