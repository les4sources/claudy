# Les demandes de reconstruction du site les4sources.be (voir
# `WebsiteRebuildJob`). Elles vivaient dans un verrou du cache fichier, qui ne
# connaît pas l'expiration pour `unless_exist` : un seul job perdu (redémarrage
# pendant les deux minutes d'attente) figeait le verrou pour toujours, et plus
# aucune publication ne reconstruisait le site. En base, une demande en
# attente se voit, se rattrape et se trace.
class CreateWebsiteRebuilds < ActiveRecord::Migration[8.1]
  def change
    create_table :website_rebuilds do |t|
      t.string :status, null: false, default: "pending"
      t.string :trigger, null: false, default: "publication"
      t.datetime :requested_at, null: false
      t.datetime :last_requested_at, null: false
      t.integer :requests_count, null: false, default: 1
      t.datetime :dispatched_at
      t.string :response_code
      t.string :error_message

      t.timestamps
    end
    add_index :website_rebuilds, [:status, :requested_at]
  end
end
