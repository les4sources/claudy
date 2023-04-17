class AddOptionPizzaPartyToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :option_pizza_party, :boolean
  end
end
