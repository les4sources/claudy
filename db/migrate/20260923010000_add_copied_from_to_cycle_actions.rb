# Copier une action au cycle suivant (epic #330, phase 4). La flèche existante
# DÉPLACE (et porte `deferred_from_id`, dont vit `undo_defer_next`) ; la copie,
# elle, DUPLIQUE sans toucher à l'origine : son lien a donc sa propre colonne.
#
# L'index est unique sur les lignes vivantes : jamais deux copies non supprimées
# pour une même action (décision 6), même en cliquant vite. Une copie retirée
# (soft-delete) libère la place pour une copie suivante.
class AddCopiedFromToCycleActions < ActiveRecord::Migration[8.1]
  def change
    add_reference :cycle_actions, :copied_from,
      foreign_key: { to_table: :cycle_actions },
      index: { unique: true, where: "deleted_at IS NULL" }
  end
end
