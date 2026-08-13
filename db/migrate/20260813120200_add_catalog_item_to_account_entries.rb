# Rattache une écriture à l'article consommé (issue #157).
#
# Nullable : une écriture de charge, de règlement ou de cagnotte ne pointe
# aucun article. L'écriture continue par ailleurs de FIGER son
# `unit_price_cents` — corriger un palier rétroactivement ne doit pas déplacer
# un décompte déjà émis.
class AddCatalogItemToAccountEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :account_entries, :catalog_item, foreign_key: true
  end
end
