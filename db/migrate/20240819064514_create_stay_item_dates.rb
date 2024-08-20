class CreateStayItemDates < ActiveRecord::Migration[7.0]
  def change
    create_table :stay_item_dates do |t|

      t.references :booked_item, polymorphic: true, null: false
      t.date :booking_date, null: false
      t.references :stay, null: false, foreign_key: true

      t.timestamps
    end

    add_index :stay_item_dates, [:booked_item_type, :booked_item_id, :booking_date], unique: true, name: 'index_stay_item_dates_on_item_and_date'
  
  end
end
