class CreatePayments < ActiveRecord::Migration[7.0]
  def change
    create_table :payments do |t|
      t.references :booking, null: false, foreign_key: true
      t.string :payment_method
      t.string :status
      t.timestamp :deleted_at

      t.timestamps
    end

    add_monetize :payments, :amount, amount: { null: false }, currency: { present: false }
  end
end
