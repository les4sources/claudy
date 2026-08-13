# Comptes courants internes, phase 1 du lot A (issue #155).
#
# Un ménage = un foyer des 4 Sources. `kind` distingue les habitants du lieu
# (`resident`) des membres du collectif qui n'y vivent pas (`member`) : les deux
# consomment au bar et à l'épicerie, seuls les premiers paient des charges.
class CreateHouseholds < ActiveRecord::Migration[7.2]
  def change
    create_table :households do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "resident"
      t.date :moved_in_on
      t.date :moved_out_on
      t.text :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :households, :deleted_at
  end
end
