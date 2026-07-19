class CreateSettings < ActiveRecord::Migration[7.0]
  # Petit magasin clé/valeur pour les paramètres globaux du domaine ajustables
  # SANS redéploiement (issue #78). Premier usage : les capacités globales
  # camping (personnes) et van (véhicules), aujourd'hui figées en constantes.
  # Table vide par défaut → chaque paramètre absent retombe sur son défaut code.
  def change
    create_table :settings do |t|
      t.string :key, null: false
      t.string :value

      t.timestamps
    end

    add_index :settings, :key, unique: true
  end
end
