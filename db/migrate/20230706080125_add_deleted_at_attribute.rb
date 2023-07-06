class AddDeletedAtAttribute < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :deleted_at, :timestamp
    add_column :events, :deleted_at, :timestamp
    add_column :event_categories, :deleted_at, :timestamp
    add_column :lodgings, :deleted_at, :timestamp
    add_column :notes, :deleted_at, :timestamp
    add_column :reservations, :deleted_at, :timestamp
    add_column :space_reservations, :deleted_at, :timestamp
    add_column :rooms, :deleted_at, :timestamp
    add_column :spaces, :deleted_at, :timestamp
    add_column :space_bookings, :deleted_at, :timestamp
  end
end
