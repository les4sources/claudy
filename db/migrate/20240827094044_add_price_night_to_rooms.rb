class AddPriceNightToRooms < ActiveRecord::Migration[7.0]
  def change
    add_monetize :rooms, :price_night, currency: { present: false }
  end
end
