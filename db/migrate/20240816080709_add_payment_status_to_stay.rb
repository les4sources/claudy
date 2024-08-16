class AddPaymentStatusToStay < ActiveRecord::Migration[7.0]
  def change
     add_column :stays, :payment_status, :string
  end
end
