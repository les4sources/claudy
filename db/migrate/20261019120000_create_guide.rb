# Le Guide des 4 Sources (Michael, 2026-10-19) : le manuel interne du collectif,
# lu par tous les rôles. Des chapitres, des pages en Markdown, et l'historique
# de chaque page (qui a écrit quoi, quand, depuis l'écran ou depuis Claude).
class CreateGuide < ActiveRecord::Migration[8.1]
  def change
    create_table :guide_chapters do |t|
      t.string :title, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :guide_chapters, :position
    add_index :guide_chapters, :deleted_at

    create_table :guide_pages do |t|
      t.references :guide_chapter, null: false, foreign_key: true, index: false
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.integer :position, null: false, default: 0
      # Dénormalisés depuis la dernière révision : le sommaire et la page les
      # affichent sans aller chercher l'historique.
      t.references :last_editor, foreign_key: { to_table: :users }
      t.datetime :last_edited_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :guide_pages, %i[guide_chapter_id position]
    add_index :guide_pages, :deleted_at

    # Une révision = l'état COMPLET de la page après une modification (titre +
    # Markdown). Jamais réécrite : restaurer une version en crée une nouvelle.
    create_table :guide_page_revisions do |t|
      t.references :guide_page, null: false, foreign_key: true, index: false
      t.references :user, foreign_key: true
      t.string :title, null: false
      t.text :body, null: false, default: ""
      # « web » (l'éditeur de Claudy) ou « mcp » (Claude, au nom de `user`).
      t.string :source, null: false, default: "web"
      t.string :summary
      t.datetime :created_at, null: false
    end
    add_index :guide_page_revisions, %i[guide_page_id created_at]
  end
end
