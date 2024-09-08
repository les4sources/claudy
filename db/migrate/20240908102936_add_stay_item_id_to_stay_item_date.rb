class AddStayItemIdToStayItemDate < ActiveRecord::Migration[7.0]
  
  def change
    add_reference :stay_item_dates, :stay_item, null: true, foreign_key: true
  end

end
