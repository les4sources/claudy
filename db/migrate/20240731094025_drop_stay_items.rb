class DropStayItems < ActiveRecord::Migration[7.0]
  def change
    drop_table :stay_items
  end
end
