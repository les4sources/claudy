class AddLegacySpaceBookingIdToStays < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :legacy_space_booking_id, :bigint
    add_index :stays, :legacy_space_booking_id
  end
end 