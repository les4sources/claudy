# L'arrêté du mois (issue à venir — la feature d'apothéose du run).
#
# Une seule ligne par mois clôturé, avec qui l'a fait et quand. Ce n'est pas une
# case à cocher : on ne peut la poser que si les huit contrôles du mois sont au
# vert, et ce qui est vert se recalcule depuis les données — jamais depuis un
# état stocké qui se périme.
class CreateMonthClosings < ActiveRecord::Migration[8.1]
  def change
    create_table :month_closings do |t|
      t.date :period_month, null: false
      t.datetime :closed_at, null: false
      t.string :closed_by
      t.text :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :month_closings, :period_month, unique: true, where: "deleted_at IS NULL"
    add_index :month_closings, :deleted_at
  end
end
