# Les dimensions adultes d'une plante (en mètres), pour la dessiner à maturité
# dans la vue 3D du relief. Facultatives : sans elles, on les déduit de
# l'espèce et de la conduite (trogne, cépée…), voir `Plant#mature_dimensions`.
class AddMatureDimensionsToPlants < ActiveRecord::Migration[8.1]
  def change
    add_column :plants, :mature_height, :decimal, precision: 5, scale: 1
    add_column :plants, :mature_spread, :decimal, precision: 5, scale: 1
  end
end
