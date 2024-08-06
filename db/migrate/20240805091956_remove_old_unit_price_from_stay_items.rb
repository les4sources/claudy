class RemoveOldUnitPriceFromStayItems < ActiveRecord::Migration[7.0]
  def change
    remove_column :stay_items, :unit_price, :decimal
  end
end
