class CreateGatheringActionHumans < ActiveRecord::Migration[7.0]
  def change
    create_table :gathering_action_humans do |t|
      t.references :gathering_action, null: false, foreign_key: true
      t.references :human, null: false, foreign_key: true

      t.timestamps
    end

    add_index :gathering_action_humans, [:gathering_action_id, :human_id],
              unique: true, name: "index_gathering_action_humans_uniqueness"
  end
end
