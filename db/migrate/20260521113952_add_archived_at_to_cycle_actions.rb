class AddArchivedAtToCycleActions < ActiveRecord::Migration[7.0]
  def change
    add_column :cycle_actions, :archived_at, :datetime
    add_index :cycle_actions, [:human_id, :archived_at]
  end
end
