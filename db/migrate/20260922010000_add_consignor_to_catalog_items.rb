# Epic #359, phase 1 — un article du canal « Artisanat » appartient à un artisan.
#
# Nullable au niveau du schéma : seuls les articles `craft` exigent un artisan, et
# c'est le modèle qui le dit (une contrainte NOT NULL interdirait tous les autres
# canaux, qui n'en ont pas).
class AddConsignorToCatalogItems < ActiveRecord::Migration[8.1]
  def change
    add_reference :catalog_items, :consignor, null: true, index: true, foreign_key: true
  end
end
