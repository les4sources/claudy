class AddOriginToMealOrders < ActiveRecord::Migration[8.1]
  def up
    add_column :meal_orders, :origin, :string, null: false, default: "client"
    add_index  :meal_orders, :origin

    # Backfill explicite des lignes existantes. `client` est le cas majoritaire
    # et le seul qu'on puisse affirmer sans inventer : avant cette colonne, rien
    # ne distinguait une proposition de l'accueil d'une demande du client.
    execute "UPDATE meal_orders SET origin = 'client' WHERE origin IS NULL"
  end

  def down
    remove_index  :meal_orders, :origin
    remove_column :meal_orders, :origin
  end
end
