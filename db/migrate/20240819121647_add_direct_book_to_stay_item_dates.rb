class AddDirectBookToStayItemDates < ActiveRecord::Migration[7.0]
  def change
    add_column :stay_item_dates, :direct_book, :boolean, default: true
  end
end
