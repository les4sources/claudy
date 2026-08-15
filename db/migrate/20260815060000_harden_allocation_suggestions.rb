# Les gardes réclamées par la revue adverse (issue #183).
#
# Une seule suggestion en attente par ligne, garantie par la base : le test
# applicatif « existe-t-il déjà une suggestion ? » puis l'insertion ne sont pas
# atomiques, et deux ouvertures simultanées de l'écran en créeraient deux.
#
# Et le code transaction sur la ligne de trésorerie : le critère de règle
# correspondant cherchait dans la référence externe, où il n'a jamais été écrit.
# Une règle sur code transaction ne pouvait donc jamais correspondre — un
# critère qui ne matche rien est pire qu'un critère absent, parce qu'on croit
# l'avoir posé.
class HardenAllocationSuggestions < ActiveRecord::Migration[8.1]
  def change
    add_index :allocation_suggestions, :cash_entry_id,
              unique: true, where: "status = 'pending' AND deleted_at IS NULL",
              name: "index_one_pending_suggestion_per_entry"

    add_column :cash_entries, :transaction_code, :string
    add_index :cash_entries, :transaction_code
  end
end
