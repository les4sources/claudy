# Le pari face au réel (epic #330, phase 2) : `hours` reste l'ESTIMÉ engagé,
# `actual_hours` compte ce qui a vraiment été fait. Les deux vivent côte à côte ;
# le bilan de clôture continue de raisonner sur l'estimé (décision 3).
class AddActualHoursToCycleActions < ActiveRecord::Migration[8.1]
  def change
    add_column :cycle_actions, :actual_hours, :decimal, precision: 5, scale: 2, default: 0, null: false
  end
end
