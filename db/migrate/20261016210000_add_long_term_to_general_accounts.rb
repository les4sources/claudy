# « Peut-on dépenser ? » ne doit retirer que les prêts à rendre bientôt
# (Michael, 2026-10-16). Les certificats immobiliers se remboursent sur des
# années : les compter dans la marge des 90 jours fait dire « il manque
# 717 000 € ». Le compte dit s'il est à long terme ; par défaut il ne l'est pas,
# et le prêt reste compté (le verdict ne rassure pas par omission).
class AddLongTermToGeneralAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :general_accounts, :long_term, :boolean, default: false, null: false
  end
end
