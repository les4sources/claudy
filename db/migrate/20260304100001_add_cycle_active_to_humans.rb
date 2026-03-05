class AddCycleActiveToHumans < ActiveRecord::Migration[7.0]
  def change
    add_column :humans, :cycle_active, :boolean, default: false
  end
end
