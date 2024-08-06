class CreatePaymentRequests < ActiveRecord::Migration[7.0]
  def change
    create_table :payment_requests do |t|
      t.references :stay, null: false, foreign_key: true
      t.integer :status, default: 0

      t.timestamps
    end

    add_monetize :payment_requests, :amount, amount: { null: false }, currency: { present: false }
  end
end
