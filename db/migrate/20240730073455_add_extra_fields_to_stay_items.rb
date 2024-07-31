class AddExtraFieldsToStayItems < ActiveRecord::Migration[7.0]
  def change
     add_column :stay_items, :start_date, :date
     add_column :stay_items, :end_date, :date
     add_column :stay_items, :duration, :string
     add_column :stay_items, :notes, :text
     add_column :stay_items, :adults, :integer
     add_column :stay_items, :children, :integer
     add_column :stay_items, :babies, :integer
  end
end
