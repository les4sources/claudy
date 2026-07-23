class CreateHamacBookings < ActiveRecord::Migration[7.0]
  def change
    create_table :hamac_bookings do |t|
      t.string  :firstname
      t.string  :lastname
      t.string  :email
      t.string  :phone
      t.string  :group_name
      t.date    :from_date
      t.date    :to_date
      t.string  :kind,        null: false, default: "simple"
      t.integer :count,       null: false, default: 1
      t.string  :status
      t.integer :price_cents
      t.string  :token
      t.text    :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :hamac_bookings, :token, unique: true
    add_index :hamac_bookings, [:from_date, :to_date]
    add_index :hamac_bookings, :deleted_at
  end
end
