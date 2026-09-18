# Une Pizza Party privée réservée et payée sur Tranches de Vie, rattachée à la
# main au séjour de groupe géré ici (issue #339). Elle s'ajoute au total du
# séjour et son paiement compte dans l'encaissé, pour que la facture reflète le
# total party comprise.
class CreatePartyReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :party_reservations do |t|
      t.references :stay, null: false, foreign_key: true
      t.references :payment, type: :uuid, foreign_key: true

      t.string  :source, null: false, default: "tranchesdevie"
      t.integer :external_id, null: false
      t.string  :external_number
      t.date    :held_on
      t.string  :slot
      t.string  :group_name
      t.integer :persons
      t.boolean :forfait, null: false, default: false
      t.integer :price_cents, null: false, default: 0
      t.string  :status, null: false, default: "active"

      t.datetime :external_paid_at
      t.string   :external_admin_url
      t.datetime :external_refunded_at
      t.datetime :synced_at
      t.jsonb    :payload

      t.datetime :deleted_at

      t.timestamps
    end

    add_index :party_reservations, :deleted_at
    add_index :party_reservations, :status
    # Une même commande Tranches de Vie ne se rattache qu'à UN seul séjour.
    add_index :party_reservations, %i[source external_id], unique: true, where: "deleted_at IS NULL",
              name: "index_party_reservations_on_source_and_external_id_live"
  end
end
