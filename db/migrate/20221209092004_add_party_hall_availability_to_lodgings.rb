class AddPartyHallAvailabilityToLodgings < ActiveRecord::Migration[7.0]
  def change
    add_column :lodgings, :party_hall_availability, :boolean
  end
end
