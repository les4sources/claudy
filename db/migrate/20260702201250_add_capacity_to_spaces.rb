class AddCapacityToSpaces < ActiveRecord::Migration[7.0]
  def change
    # Nombre de groupes (bookings confirmés) pouvant occuper l'espace le même
    # jour. 1 = espace exclusif (salles). >1 = espace multi-groupe (camping :
    # Bois, Pâture est, Pâture ouest). Défaut 1 → comportement historique.
    add_column :spaces, :capacity, :integer, default: 1, null: false
  end
end
