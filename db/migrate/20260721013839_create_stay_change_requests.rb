class CreateStayChangeRequests < ActiveRecord::Migration[7.0]
  def change
    create_table :stay_change_requests do |t|
      t.references :stay, null: false, foreign_key: true
      t.jsonb :draft_snapshot, null: false, default: {}
      t.integer :new_total_cents, null: false, default: 0
      t.integer :delta_cents, null: false, default: 0
      t.string :refund_iban
      t.string :status, null: false, default: "pending"
      t.text :refusal_reason
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :stay_change_requests, [:stay_id, :status]
    add_index :stay_change_requests, :deleted_at
  end
end
