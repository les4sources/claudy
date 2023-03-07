class CreateSpaceBookings < ActiveRecord::Migration[7.0]
  def change
    create_table :space_bookings do |t|
      t.string :firstname
      t.string :lastname
      t.string :group_name
      t.string :phone
      t.string :email
      t.date :from_date
      t.date :to_date
      t.string :status
      t.string :tier
      t.string :payment_status
      t.string :invoice_status
      t.string :contract_status
      t.text :notes
      t.string :token

      t.timestamps
    end

    add_monetize :space_bookings, :price, amount: { null: true, default: nil }, currency: { present: false }
  end
end
