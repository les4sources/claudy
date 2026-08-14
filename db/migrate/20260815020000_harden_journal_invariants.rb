# Les gardes que la revue adverse a réclamées (issue #177).
#
# Une contre-passation par écriture, et pas deux : le test applicatif se fait
# hors transaction, donc deux clics simultanés produiraient deux miroirs et le
# solde s'inverserait. L'index tranche là où le code hésite.
class HardenJournalInvariants < ActiveRecord::Migration[8.1]
  def change
    add_index :journal_entries, :reversal_of_id,
              unique: true, where: "reversal_of_id IS NOT NULL",
              name: "index_journal_entries_on_single_reversal"
  end
end
