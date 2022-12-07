class AddLodgingReferenceToBookings < ActiveRecord::Migration[7.0]
  def change
    add_reference :bookings, :lodging, null: true, foreign_key: true
  end
end
