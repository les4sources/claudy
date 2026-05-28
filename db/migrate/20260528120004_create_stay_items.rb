class CreateStayItems < ActiveRecord::Migration[7.0]
  def change
    create_table :stay_items do |t|
      t.references :stay, foreign_key: true, null: false
      t.string :bookable_type, null: false
      t.bigint :bookable_id, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :stay_items, [:bookable_type, :bookable_id]
    # A given bookable can only be attached once to a given stay. Partial so a
    # soft-deleted join doesn't block re-attachment.
    add_index :stay_items, [:stay_id, :bookable_type, :bookable_id],
              unique: true, where: "deleted_at IS NULL",
              name: "index_stay_items_on_stay_and_bookable_unique_live"
  end
end
