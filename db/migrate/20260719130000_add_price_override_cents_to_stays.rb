# Prix libre / override du séjour (epic #81, Phase 3). Colonne additive nullable :
# quand elle est renseignée, elle IMPOSE le total du séjour et court-circuite le
# devis B2C forfaitaire. Vide (NULL) = comportement historique (devis appliqué).
class AddPriceOverrideCentsToStays < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :price_override_cents, :integer
  end
end
