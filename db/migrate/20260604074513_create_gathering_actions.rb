class CreateGatheringActions < ActiveRecord::Migration[7.0]
  def change
    create_table :gathering_actions do |t|
      t.references :gathering, null: false, foreign_key: true
      t.string :label, null: false
      t.boolean :completed, null: false, default: false
      t.datetime :completed_at
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :gathering_actions, :deleted_at
    add_index :gathering_actions, [:gathering_id, :position]
  end
end
