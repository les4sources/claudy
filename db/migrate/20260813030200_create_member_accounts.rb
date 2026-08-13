# Comptes courants (issue #155).
#
# Un compte est ANCRÉ sur exactement une chose : un ménage, une personne, ou
# rien du tout (`entity` — Semisto, Low tech, Collations…, qui sont de vraies
# colonnes du récapitulatif petite restauration et ne sont ni des sourciers ni
# des ménages). La contrainte CHECK tient cet invariant EN BASE : un compte
# incohérent est impossible, y compris depuis une console ou un import.
#
# Aucune colonne de solde : `MemberAccount#balance_cents` recalcule toujours
# depuis `opening_balance_cents` + les écritures. Un solde stocké finit par
# diverger de ses lignes, et on ne sait plus laquelle des deux ment.
class CreateMemberAccounts < ActiveRecord::Migration[7.2]
  def change
    create_table :member_accounts do |t|
      t.string :kind, null: false
      t.references :household, foreign_key: true
      t.references :human, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.string :contact_email
      t.bigint :opening_balance_cents, null: false, default: 0
      t.date :opening_balance_on
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :member_accounts, :code, unique: true
    add_index :member_accounts, :deleted_at

    add_check_constraint :member_accounts,
                         "(kind = 'household' AND household_id IS NOT NULL AND human_id IS NULL) " \
                         "OR (kind = 'human' AND human_id IS NOT NULL AND household_id IS NULL) " \
                         "OR (kind = 'entity' AND household_id IS NULL AND human_id IS NULL)",
                         name: "member_accounts_anchor_check"
  end
end
