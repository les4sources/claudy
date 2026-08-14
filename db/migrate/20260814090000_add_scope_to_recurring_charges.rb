# Une charge récurrente peut viser un GROUPE de ménages (Michael, 2026-08-14).
#
# Le forfait charges vaut pour tous les ménages habitants. Le recopier ménage
# par ménage, c'est garantir que la prochaine famille qui arrive sera oubliée —
# exactement le genre d'oubli dont la note de passation est pleine. Une règle
# porte donc désormais son périmètre, et la génération le résout au moment où
# elle tourne : un ménage créé après coup est couvert sans que personne n'y
# pense.
#
# `member_account_id` devient nullable, et la contrainte tient l'ancrage : soit
# un compte précis, soit un périmètre — jamais les deux, jamais aucun.
class AddScopeToRecurringCharges < ActiveRecord::Migration[8.1]
  def change
    add_column :recurring_charges, :applies_to, :string, null: false, default: "account"
    change_column_null :recurring_charges, :member_account_id, true

    add_check_constraint :recurring_charges,
                         "(applies_to = 'account' AND member_account_id IS NOT NULL) " \
                         "OR (applies_to <> 'account' AND member_account_id IS NULL)",
                         name: "recurring_charges_scope_check"
  end
end
