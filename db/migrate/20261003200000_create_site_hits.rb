# Statistiques du site www.les4sources.be, sans cookie (2026-10-03).
#
# `site_hits` reçoit une ligne par page vue ou par événement (clic sortant,
# envoi Tally, étape du funnel /reservation). Aucune colonne ne garde l'IP ni
# le User-Agent : on n'en conserve que l'empreinte du jour (`visitor_hash`) et
# des catégories déjà réduites (appareil, navigateur, OS, pays).
#
# `site_visit_salts` tient le sel aléatoire du jour qui entre dans l'empreinte.
# Il est détruit dès le lendemain : passé minuit, plus personne ne peut relier
# deux journées d'un même visiteur, ni retrouver une IP en essayant toutes les
# adresses possibles.
class CreateSiteHits < ActiveRecord::Migration[8.1]
  def change
    create_table :site_hits do |t|
      t.datetime :occurred_at, null: false
      t.date :day, null: false
      t.string :kind, null: false
      t.string :name
      t.string :path, null: false
      t.string :target
      t.string :visitor_hash, null: false
      t.string :referrer_host
      t.string :source
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.string :device
      t.string :browser
      t.string :os
      t.string :country
      t.timestamps
    end
    add_index :site_hits, :occurred_at
    add_index :site_hits, [:day, :visitor_hash]
    add_index :site_hits, [:kind, :name]

    create_table :site_visit_salts do |t|
      t.date :day, null: false
      t.string :salt, null: false
      t.timestamps
    end
    add_index :site_visit_salts, :day, unique: true
  end
end
