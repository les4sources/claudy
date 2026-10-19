# Chapitres du Guide par rôle (Michael, 2026-10-19) : chaque chapitre dit quels
# rôles le lisent ; les Sourciers lisent tout. Les chapitres existants restent
# ouverts aux rôles qui lisaient déjà tout le Guide, rien ne change pour eux le
# jour du déploiement. Les porteurs d'activité, qui n'ouvraient pas le Guide,
# n'ont encore aucun chapitre.
class AddAccessRolesToGuideChapters < ActiveRecord::Migration[8.1]
  def up
    add_column :guide_chapters, :access_roles, :string, array: true, default: [], null: false
    execute "UPDATE guide_chapters SET access_roles = '{communication,kid,administratif,anier}'"
  end

  def down
    remove_column :guide_chapters, :access_roles
  end
end
