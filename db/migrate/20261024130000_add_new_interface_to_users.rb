# Nouvelle interface (redesign, Michael 2026-10-24) : chaque compte choisit
# l'interface qu'il voit. L'ancienne reste celle par défaut tant que la nouvelle
# n'a pas fait ses preuves sur les vraies données ; on bascule et on revient en
# un clic, sans rien perdre.
class AddNewInterfaceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :new_interface, :boolean, default: false, null: false
  end
end
