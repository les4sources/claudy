# Un virement couvre parfois PLUSIEURS postes : chez Seb, 280 € par mois
# payaient 230 € de charges et 50 € de location du dôme. Le lien
# `account_settlements.account_entry_id` n'en portait qu'un seul, si bien que la
# reprise a tout imputé aux charges — 2 100 € de dôme apparaissent impayés en
# face de 2 260 € d'avance sur les charges, pour de l'argent bel et bien versé.
#
# La colonne inverse permet à UN règlement de porter une écriture PAR POSTE.
# `account_entry_id` reste en place et pointe la première : rien de ce qui
# existe ne bouge, et la ventilation s'ajoute par-dessus.
class AddAccountSettlementToAccountEntries < ActiveRecord::Migration[8.1]
  def up
    add_reference :account_entries, :account_settlement, null: true, foreign_key: true, index: true

    # Le lien existant, retourné. Sans ce report, les 755 règlements déjà
    # encodés n'auraient pas de ventilation et le grand livre cesserait
    # d'afficher leur communication du jour au lendemain.
    execute <<~SQL.squish
      UPDATE account_entries
         SET account_settlement_id = account_settlements.id
        FROM account_settlements
       WHERE account_settlements.account_entry_id = account_entries.id
         AND account_entries.account_settlement_id IS NULL
    SQL
  end

  def down
    remove_reference :account_entries, :account_settlement, foreign_key: true
  end
end
