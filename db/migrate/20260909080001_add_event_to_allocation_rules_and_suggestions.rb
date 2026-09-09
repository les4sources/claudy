# Epic #245, phase 2 — rattacher une recette à son événement.
#
# La règle porte l'événement en OPTION : « la communication contient STAGE
# LOWTECH » propose alors le compte, le pôle ET l'événement d'un seul geste. La
# suggestion le transporte jusqu'à l'écran — mais elle ne crée toujours aucune
# allocation (invariant B4) : elle propose, un humain tranche.
#
# L'allocation elle-même n'a pas besoin de colonne : `document` y est déjà
# polymorphe.
class AddEventToAllocationRulesAndSuggestions < ActiveRecord::Migration[8.1]
  def change
    add_reference :allocation_rules, :event, foreign_key: true, null: true
    add_reference :allocation_suggestions, :event, foreign_key: true, null: true
  end
end
