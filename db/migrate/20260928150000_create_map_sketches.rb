# Carte du domaine (epic #348, phase 12) : les notes manuscrites, dessinées à
# main levée par-dessus la carte (stylet, doigt, souris).
#
# Choix (documenté) : la table porte elle-même `name` et `folder` ; il n'y a PAS
# de `MapLayer` par dessin. Un dessin n'a ni objets, ni barre Geoman, ni ordre
# dans le panneau des couches : lui créer une couche doublerait le nom et la
# suppression sans rien apporter.
#
# `strokes` : un tableau de tracés `{ id, points: [[lat, lng], …], width }`,
# remplacé en bloc à chaque enregistrement automatique. `lock_version` est le
# verrou optimiste de Rails : un dessin modifié ailleurs entre-temps refuse
# l'écriture (409) au lieu d'écraser les tracés de l'autre.
class CreateMapSketches < ActiveRecord::Migration[8.1]
  def change
    create_table :map_sketches do |t|
      t.string :name, null: false
      t.string :folder
      t.jsonb :strokes, null: false, default: []
      t.references :created_by, foreign_key: { to_table: :users }
      t.integer :lock_version, null: false, default: 0
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :map_sketches, :deleted_at
  end
end
