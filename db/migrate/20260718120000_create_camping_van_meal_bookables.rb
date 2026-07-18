class CreateCampingVanMealBookables < ActiveRecord::Migration[7.0]
  def change
    # Camping (tente) — occupe le calendrier via StayItem polymorphe. Capacité
    # GLOBALE du terrain (pas d'emplacements nommés) : un CampingBooking occupe
    # `people` personnes sur [from_date, to_date). Tarif €/pers/nuit (Catalog).
    create_table :camping_bookings do |t|
      t.string  :firstname
      t.string  :lastname
      t.string  :email
      t.string  :phone
      t.string  :group_name
      t.date    :from_date
      t.date    :to_date
      t.integer :people, default: 1, null: false
      t.string  :kind, default: "tente", null: false
      t.string  :status
      t.integer :price_cents
      t.string  :token
      t.text    :notes
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :camping_bookings, :deleted_at
    add_index :camping_bookings, [:from_date, :to_date]

    # Van / camping-car — occupe le calendrier via StayItem. Capacité GLOBALE
    # (nombre de véhicules) sur [from_date, to_date). Tarif forfait/nuit/véhicule.
    create_table :van_bookings do |t|
      t.string  :firstname
      t.string  :lastname
      t.string  :email
      t.string  :phone
      t.string  :group_name
      t.date    :from_date
      t.date    :to_date
      t.integer :vehicles, default: 1, null: false
      t.string  :status
      t.integer :price_cents
      t.string  :token
      t.text    :notes
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :van_bookings, :deleted_at
    add_index :van_bookings, [:from_date, :to_date]

    # Repas — commande datée rattachée DIRECTEMENT au séjour (pas d'occupation
    # calendrier, pas de StayItem). `date` nullable pour tolérer les repas du
    # funnel public (forme `{kind, people}` sans date). Tarif €/pers (Catalog).
    create_table :meal_orders do |t|
      t.references :stay, null: false, foreign_key: true
      t.string  :kind
      t.date    :date
      t.integer :people, default: 1, null: false
      t.integer :price_cents
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :meal_orders, :deleted_at
  end
end
