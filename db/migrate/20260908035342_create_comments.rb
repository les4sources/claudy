# Epic #242, phase 1 — les commentaires polymorphes. Tout « recording » de
# Claudy (rassemblement, séjour, et demain note de frais ou facture) devient
# commentable sans nouvelle table.
class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :commentable, polymorphic: true, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :comments, :deleted_at
    # Le fil se lit toujours dans l'ordre chronologique d'un objet donné.
    add_index :comments, %i[commentable_type commentable_id created_at],
              name: "index_comments_on_commentable_and_created_at"
  end
end
