class AddCalculatedPriceToStayItems < ActiveRecord::Migration[7.0]
  def change
    add_monetize :stay_items, :calculated_price, currency: { present: false }
  end
end
