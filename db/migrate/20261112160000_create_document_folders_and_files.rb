# La section Documents (Michael, 2026-11-12) : des dossiers emboîtés et des
# fichiers rangés dedans (le fichier lui-même est une pièce Active Storage).
# `deleted_at` = à la corbeille : rien ne disparaît d'un clic, on peut
# restaurer, et seul « Supprimer définitivement » efface le fichier.
class CreateDocumentFoldersAndFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :document_folders do |t|
      t.string :name, null: false
      t.references :parent, foreign_key: { to_table: :document_folders }
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :document_folders, :deleted_at

    create_table :document_files do |t|
      t.string :name, null: false
      t.references :document_folder, foreign_key: true
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :document_files, :deleted_at
  end
end
