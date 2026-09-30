# Jev ne se demande qu'une fois par ligne : sans ce repère, une ligne à laquelle
# il n'a pas su répondre serait redemandée à chaque ouverture de l'écran.
#
# Le « précédent du même IBAN » cesse d'être une source de suggestions (juste
# une fois sur deux, mesuré sur 2025). Ses propositions encore en attente sont
# retirées — supprimées en douceur, l'historique des décisions reste intact — pour
# laisser la place aux règles et à Jev.
class AddJevCheckedAtToCashEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :cash_entries, :jev_checked_at, :datetime

    execute <<~SQL.squish
      UPDATE allocation_suggestions SET deleted_at = NOW()
      WHERE source = 'iban_history' AND status = 'pending' AND deleted_at IS NULL
    SQL
  end

  def down
    remove_column :cash_entries, :jev_checked_at
  end
end
