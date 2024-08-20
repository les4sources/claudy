class RemoveIndexFromStayItemDates < ActiveRecord::Migration[7.0]
   def change
    remove_index :stay_item_dates, name: "index_stay_item_dates_on_item_and_date"
  end
end
