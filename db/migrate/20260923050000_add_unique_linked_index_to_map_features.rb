# Carte du jour (epic #348, phase 3) : un gîte ou une salle n'a qu'UN tracé.
# Sans cette garantie en base, deux objets reliés au même gîte afficheraient
# deux fois son occupation, et le panneau ne saurait pas lequel ouvrir. Index
# partiel : un objet supprimé (soft-delete) libère le gîte pour un nouveau tracé.
class AddUniqueLinkedIndexToMapFeatures < ActiveRecord::Migration[8.1]
  def change
    add_index :map_features, %i[linked_type linked_id], unique: true,
              where: "deleted_at IS NULL AND linked_id IS NOT NULL",
              name: "index_map_features_on_linked_unique_live"
  end
end
