class AddEconomicToCycleActions < ActiveRecord::Migration[8.1]
  def change
    add_column :cycle_actions, :economic, :boolean, null: false, default: false
    add_index  :cycle_actions, :economic
  end
end
