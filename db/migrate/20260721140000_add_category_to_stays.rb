class AddCategoryToStays < ActiveRecord::Migration[7.0]
  def change
    # Catégorie de séjour (mariage, formation, groupe d'amis…). Nullable : tout
    # l'historique importé (legacy Tally / OTA) n'a jamais porté cette info, et
    # le funnel public la laisse optionnelle. Clé stable anglaise en base ;
    # libellé FR à l'affichage (Stay::CATEGORIES).
    add_column :stays, :category, :string
  end
end
