# Apporteur d'un séjour (Michael, 2026-10-18). La page « Les 4 Sources » du
# nouveau site de Semisto envoie ses visiteurs sur
# `/reservation?ref=semisto` : un séjour réservé par ce lien doit le dire, pour
# que l'équipe voie ce que Semisto amène et puisse lui reverser sa part.
#
# DISTINCT de `source` (le canal : funnel, import Tally, OTA, saisie manuelle) :
# un séjour apporté par Semisto passe par le funnel comme les autres, son canal
# reste `reservation`. Nullable — la très grande majorité des séjours n'a pas
# d'apporteur. Index partiel : le filtre de l'index ne lit que les séjours qui
# en ont un.
class AddReferralToStays < ActiveRecord::Migration[8.1]
  def change
    add_column :stays, :referral, :string
    add_index :stays, :referral, where: "referral IS NOT NULL"
  end
end
