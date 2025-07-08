class AddLegacyBookingIdToStays < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :legacy_booking_id, :bigint, comment: "Référence vers l'ancien booking migré"
    add_index :stays, :legacy_booking_id, name: "index_stays_on_legacy_booking_id"
  end
end
