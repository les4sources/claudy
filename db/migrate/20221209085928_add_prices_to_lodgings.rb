class AddPricesToLodgings < ActiveRecord::Migration[7.0]
  def change
    add_monetize :lodgings, :price_night, currency: { present: false }
    add_monetize :lodgings, :price_weekend, currency: { present: false }
  end
end
