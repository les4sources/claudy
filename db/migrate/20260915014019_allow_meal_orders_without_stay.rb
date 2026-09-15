# Une demande de cuisine peut exister AVANT le séjour (issue #315). Le Pôle
# Accueil reçoit des demandes de repas par téléphone bien avant qu'une
# réservation existe ; jusqu'ici il fallait inventer un séjour fantôme ou garder
# l'information hors de Claudy.
#
# `stay_id` devient nullable, et `contact_label` porte le texte libre qui dit
# pour qui la demande est faite — un nom de groupe, une personne, une école.
# La clé étrangère vers `stays` reste en place : elle tolère simplement NULL.
#
# Aucune ligne existante n'est touchée : toutes gardent leur `stay_id`.
class AllowMealOrdersWithoutStay < ActiveRecord::Migration[8.1]
  def up
    change_column_null :meal_orders, :stay_id, true
    add_column :meal_orders, :contact_label, :string
  end

  def down
    # Revenir en arrière supposerait de décider quoi faire des demandes
    # orphelines — les supprimer, ou leur inventer un séjour. Aucune des deux
    # n'est une décision qu'une migration a le droit de prendre toute seule.
    raise ActiveRecord::IrreversibleMigration,
          "Des demandes de cuisine peuvent exister sans séjour : rendre stay_id " \
          "obligatoire à nouveau demande de trancher leur sort à la main."
  end
end
