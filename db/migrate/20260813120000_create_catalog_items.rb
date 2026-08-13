# Catalogue du bar et du cellier (issue #157).
#
# Un article ne porte AUCUN prix : les prix vivent dans `catalog_prices`, par
# paliers datés. C'est ce qui permet de créer un palier au 1er septembre sans
# changer le prix résolu au 31 août — donc sans faire mentir un décompte déjà
# émis ni la reprise de l'historique.
class CreateCatalogItems < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_items do |t|
      t.string :name, null: false
      t.string :channel, null: false
      t.string :category
      t.string :unit, null: false, default: "piece"
      t.string :reference
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :catalog_items, [:channel, :name]
    add_index :catalog_items, :deleted_at
  end
end
