class DropPaymentRequests < ActiveRecord::Migration[7.0]
  

  def change
    execute "ALTER TABLE payments DROP CONSTRAINT fk_rails_d6c292006a CASCADE"
    drop_table :payment_requests_stay_items
    drop_table :payment_requests
  end

 
end
