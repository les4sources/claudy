class AddFinalPriceToStays < ActiveRecord::Migration[7.0]
  def change
    add_monetize :stays, :final_price, currency: { present: false }
  end
end

