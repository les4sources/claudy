# Les targets d'un membre sur un cycle (epic #330, phase 3).
#
# Un cycle porte des actions — ce qu'on fait — mais rien qui dise ce qu'on
# VISE. La target est cette intention : une phrase, une case à cocher, et la
# possibilité de dire à la clôture qui a atteint quoi.
class CreateCycleTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :cycle_targets do |t|
      t.references :human, null: false, foreign_key: true
      t.references :cycle, null: false, foreign_key: true
      t.string :label, null: false
      # `achieved_at` plutôt qu'un booléen : savoir QUAND une intention a été
      # atteinte vaut mieux que savoir seulement qu'elle l'a été.
      t.datetime :achieved_at
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :cycle_targets, [:human_id, :cycle_id, :position]
  end
end
