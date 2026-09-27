# Carte du domaine (epic #348, phase 11) : commenter un endroit et en discuter
# en fil. Le point de la carte (`map_features`, `feature_kind` `comment`, couche
# `comments`) porte UN fil : un message racine (`parent_id` nul) et ses
# réponses, qui pointent toutes vers la racine. `resolved_at` n'a de sens que
# sur la racine : c'est le fil entier qui est résolu.
class CreateMapComments < ActiveRecord::Migration[8.1]
  def change
    create_table :map_comments do |t|
      t.references :map_feature, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :map_comments }
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :resolved_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :map_comments, :deleted_at
  end
end
