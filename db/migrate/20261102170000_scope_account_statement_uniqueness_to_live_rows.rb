# Un décompte émis trop tôt (jamais envoyé) peut désormais être régénéré : il
# part à la corbeille et un nouveau décompte du même mois le remplace. L'index
# unique (compte, mois) doit donc ignorer les décomptes à la corbeille, sinon
# le remplaçant se heurterait à son prédécesseur supprimé.
class ScopeAccountStatementUniquenessToLiveRows < ActiveRecord::Migration[8.1]
  def change
    remove_index :account_statements, %i[member_account_id period_month], unique: true,
                 name: "index_account_statements_on_member_account_id_and_period_month"
    add_index :account_statements, %i[member_account_id period_month], unique: true,
              where: "deleted_at IS NULL",
              name: "index_account_statements_on_member_account_id_and_period_month"
  end
end
