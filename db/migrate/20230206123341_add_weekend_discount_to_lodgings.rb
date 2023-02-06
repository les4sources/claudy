class AddWeekendDiscountToLodgings < ActiveRecord::Migration[7.0]
  def change
    remove_column :lodgings, :price_weekend_cents, :integer
    add_monetize :lodgings, :weekend_discount, currency: { present: false }
  end
end
