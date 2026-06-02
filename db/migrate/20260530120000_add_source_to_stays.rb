class AddSourceToStays < ActiveRecord::Migration[7.0]
  # Tranche 2 (Q9 / AC-T2-22 / AC-T2-22b).
  #
  # Canal d'attribution d'un Stay. DISTINCT de `legacy_origin` (clé
  # d'import/dédup de la migration legacy, index unique, NE PAS confondre ni
  # réutiliser). Tout Stay créé via /reservation porte source == "reservation"
  # (le défaut), ce qui permet au Pôle Accueil d'observer la transition Tally →
  # funnel natif.
  #
  # Valeurs admises : reservation / tally_legacy / ota / manual.
  def change
    add_column :stays, :source, :string, null: false, default: "reservation"
    add_index :stays, :source
  end
end
