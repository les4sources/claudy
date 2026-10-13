# Rôles d'accès (Michael, 2026-10-09) : un compte porte un ou plusieurs rôles
# (Sourcier, Communication, Kid, Administratif) qui ouvrent des sections de
# l'app, cf. `Access`. Les comptes existants avaient tout : ils deviennent
# Sourciers, rien ne change pour eux le jour du déploiement. Un compte créé
# ensuite naît sans rôle, un Sourcier lui en donne dans Paramètres › Accès.
class AddAccessRolesToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :access_roles, :string, array: true, default: [], null: false
    execute "UPDATE users SET access_roles = '{sourcier}'"
  end

  def down
    remove_column :users, :access_roles
  end
end
