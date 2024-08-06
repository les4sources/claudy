class ChangeUnitPriceToUnitPriceCents < ActiveRecord::Migration[7.0]
  
  def change
    add_monetize :stay_items, :unit_price, default: 0, null: false
  end
  
end