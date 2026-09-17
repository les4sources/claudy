# Une action de cycle peut se répéter dans le cycle (un batchcooking de 11 h
# fait 3 fois). On saisit la durée d'UNE fois et le nombre de fois ; `hours`
# reste le total engagé, la colonne que tout le monde additionne.
class AddOccurrencesToCycleActions < ActiveRecord::Migration[8.1]
  def up
    add_column :cycle_actions, :unit_hours, :decimal, precision: 5, scale: 2
    add_column :cycle_actions, :occurrences, :integer, null: false, default: 1
    add_column :cycle_actions, :completed_occurrences, :integer, null: false, default: 0

    execute <<~SQL.squish
      UPDATE cycle_actions
      SET unit_hours = hours,
          occurrences = 1,
          completed_occurrences = CASE WHEN completed THEN 1 ELSE 0 END
    SQL
  end

  def down
    remove_column :cycle_actions, :completed_occurrences
    remove_column :cycle_actions, :occurrences
    remove_column :cycle_actions, :unit_hours
  end
end
