class DropPaymentRequests < ActiveRecord::Migration[7.0]
  def change
    drop_table :payment_requests_stay_items
    drop_table :payment_requests
  end
end
