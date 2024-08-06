class CreatePaymentRequestsStayItems < ActiveRecord::Migration[7.0]
  def change
    create_table :payment_requests_stay_items do |t|
      t.references :payment_request, null: false, foreign_key: true
      t.references :stay_item, null: false, foreign_key: true

      t.timestamps
    end
  end
end
