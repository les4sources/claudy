# Barèmes datés (issue #156, lot A phase 2). Un `Rate` n'avait qu'une valeur :
# celle d'aujourd'hui. `rate_versions` lui donne une dimension temporelle sans
# rien changer aux 47 clés existantes — `rates.amount_cents` reste le miroir de
# la version qui couvre le jour même, donc tous les appels
# `Pricing::Rates.cents(key)` gardent exactement le même comportement.
class CreateRateVersions < ActiveRecord::Migration[7.2]
  def change
    create_table :rate_versions do |t|
      t.references :rate, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.date :active_from, null: false
      t.date :active_until
      t.string :note

      t.timestamps
    end

    # Une seule version peut démarrer un jour donné pour une clé : c'est ce qui
    # rend `Rates::UpdateAmount` réentrant (deux éditions le même jour éditent
    # la même ligne au lieu d'en empiler deux). L'index sert aussi la lecture
    # datée `Pricing::Rates.cents(key, on:)`.
    add_index :rate_versions, [:rate_id, :active_from], unique: true
  end
end
