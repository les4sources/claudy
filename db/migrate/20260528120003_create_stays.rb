class CreateStays < ActiveRecord::Migration[7.0]
  def change
    create_table :stays do |t|
      t.references :customer, foreign_key: true, null: false
      t.date :arrival_date
      t.date :departure_date
      t.string :status
      t.integer :total_amount_cents, default: 0, null: false
      t.text :notes
      t.string :legacy_origin
      t.datetime :deleted_at

      t.timestamps
    end

    # Idempotency marker for the legacy migration: at most one Stay per legacy
    # source record. Partial unique index so soft-deleted stays don't block it.
    add_index :stays, :legacy_origin, unique: true,
              where: "legacy_origin IS NOT NULL AND deleted_at IS NULL",
              name: "index_stays_on_legacy_origin_unique_live"
  end
end
