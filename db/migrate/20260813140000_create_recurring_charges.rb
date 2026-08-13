# Charges qui se répètent tous les mois (issue #159).
#
# Une règle porte SOIT un montant fixe, SOIT une clé de barème — jamais les
# deux, jamais aucune : la contrainte CHECK le tient en base. Une clé permet au
# montant de suivre les barèmes datés (#156) sans réécrire la règle, et surtout
# de recalculer un mois passé avec la valeur DE CE MOIS-LÀ.
#
# `split_rate_key` scinde la ligne en deux : c'est la part balançoire des 10 €
# de cagnotte, dont la version de barème est close au 30 avril 2027. Quand elle
# ne résout plus rien, la génération produit une ligne unique du montant total —
# sans changement de code et sans déploiement à cette date.
class CreateRecurringCharges < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_charges do |t|
      t.references :member_account, null: false, foreign_key: true
      t.references :household_member, foreign_key: true
      t.string :kind
      t.string :label, null: false
      t.string :flow
      t.string :basis, null: false, default: "flat"
      t.integer :amount_cents
      t.string :rate_key
      t.string :split_rate_key
      t.string :split_label
      t.date :starts_on, null: false
      t.date :ends_on
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :recurring_charges, :deleted_at

    add_check_constraint :recurring_charges,
                         "(amount_cents IS NOT NULL AND rate_key IS NULL) " \
                         "OR (amount_cents IS NULL AND rate_key IS NOT NULL)",
                         name: "recurring_charges_amount_source_check"
  end
end
