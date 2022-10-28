class CreateBookings < ActiveRecord::Migration[7.0]
  def change
    create_table :bookings do |t|
      t.string :firstname
      t.string :lastname
      t.string :phone
      t.string :email
      t.date :from_date
      t.date :to_date
      t.string :status
      t.integer :adults
      t.integer :children
      t.integer :price_cents
      t.string :payment_status
      t.string :payment_method
      t.boolean :bedsheets
      t.boolean :towels
      t.text :notes

      t.timestamps
    end
  end
end
