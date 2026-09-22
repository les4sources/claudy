# Epic #359, phase 1 — l'interrupteur « accès à l'espace artisan ».
#
# Fermé par défaut : ouvrir l'espace est un geste explicite de l'administration,
# qui oblige du même coup à renseigner l'email (validation côté modèle).
class AddPortalEnabledToConsignors < ActiveRecord::Migration[8.1]
  def change
    add_column :consignors, :portal_enabled, :boolean, null: false, default: false
  end
end
