# Consommations du bar d'un groupe (Michael, 2026-10-13). Au bar, on donne aux
# groupes une feuille où ils notent ce qu'ils prennent ; certains la rendent
# pour qu'on facture le tout avec leur séjour. Jusqu'ici, rien dans le séjour
# ne savait porter ces consommations : la photo de la feuille arrivait et
# restait sans suite.
#
# Une ligne par ARTICLE du catalogue et par séjour : réencoder la feuille met à
# jour la quantité au lieu d'ajouter un second jeu de lignes. Le prix unitaire
# est FIGÉ à l'encodage (prix public du catalogue à la date du séjour) : un
# changement de tarif ultérieur ne doit pas réécrire une facture.
class CreateBarConsumptions < ActiveRecord::Migration[8.1]
  def change
    create_table :bar_consumptions do |t|
      t.references :stay, null: false, foreign_key: true
      t.references :catalog_item, null: false, foreign_key: true
      t.string :label, null: false
      t.integer :quantity, null: false
      t.integer :unit_price_cents, null: false
      t.integer :price_cents, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :bar_consumptions, :deleted_at
    add_index :bar_consumptions, [:stay_id, :catalog_item_id],
              unique: true, where: "deleted_at IS NULL",
              name: "index_bar_consumptions_on_stay_and_item_live"
  end
end
