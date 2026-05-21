class AddPositionToCycleActions < ActiveRecord::Migration[7.0]
  def change
    add_column :cycle_actions, :position, :integer, default: 0, null: false
    add_index :cycle_actions, [:human_id, :category, :position]

    reversible do |dir|
      dir.up do
        # Seed positions per (human, category) based on existing ordering.
        execute <<~SQL
          UPDATE cycle_actions
          SET position = sub.rn
          FROM (
            SELECT id, ROW_NUMBER() OVER (
              PARTITION BY human_id, category
              ORDER BY completed ASC, COALESCE(hours, 0) DESC, created_at ASC
            ) AS rn
            FROM cycle_actions
            WHERE deleted_at IS NULL
          ) AS sub
          WHERE cycle_actions.id = sub.id
        SQL
      end
    end
  end
end
