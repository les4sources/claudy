class AddBabiesCountToStayItem < ActiveRecord::Migration[7.0]
  def change
    add_column :stay_items, :babies_count, :integer
  end
end
