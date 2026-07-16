# Table de versions PaperTrail dédiée aux Payment (issue #52).
#
# `payments` est le seul modèle à clé primaire UUID du schéma. La table
# partagée `versions` a `item_id bigint` : un UUID n'y rentre pas, donc aucune
# version n'était enregistrée pour les Payment (trou d'auditabilité, principe
# P2 de l'ISA). On isole Payment dans sa propre table `payment_versions` dont
# `item_id` est un `uuid`, sans toucher à la table `versions` partagée (qui
# continue de servir tous les autres modèles, en bigint).
class CreatePaymentVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :payment_versions do |t|
      t.string   :item_type,     null: false
      t.uuid     :item_id,       null: false
      t.string   :event,         null: false
      t.string   :whodunnit
      t.text     :object
      t.datetime :created_at
      t.text     :object_changes
    end

    add_index :payment_versions, %i[item_type item_id],
              name: "index_payment_versions_on_item_type_and_item_id"
  end
end
