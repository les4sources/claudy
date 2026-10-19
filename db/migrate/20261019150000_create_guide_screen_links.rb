# « Voir la procédure » (Michael, 2026-10-19) : un écran de Claudy renvoie à
# la page du Guide qui l'explique. L'écran est désigné par son contrôleur et
# son action (`finance/expense_reports#new`), sans les identifiants de l'URL :
# la procédure vaut pour toutes les notes de frais, pas pour une seule.
class CreateGuideScreenLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :guide_screen_links do |t|
      t.string :screen, null: false
      t.references :guide_page, null: false, foreign_key: true
      # Le titre et l'adresse de l'écran au moment du lien : la page du Guide
      # les montre (« s'ouvre depuis… »).
      t.string :label
      t.string :path
      t.references :user, foreign_key: true
      t.timestamps
    end
    add_index :guide_screen_links, :screen, unique: true
  end
end
