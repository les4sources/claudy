# La recherche de la file « À affecter » et du journal (`CashEntry.matching`)
# aplatissait TROIS colonnes à chaque requête : `translate(lower(...))` sur le
# libellé, la communication et la contrepartie de chaque ligne. Mesuré sur
# 15 000 lignes (le volume repris + une année) : ~200 ms par requête, et l'écran
# en fait deux (le compte filtré, puis la page).
#
# Le texte aplati est désormais calculé UNE fois, à l'écriture, par Postgres
# lui-même (colonne générée) : la même recherche tombe à ~10 ms, sans
# extension à installer sur le serveur (ni `unaccent`, ni `pg_trgm`).
#
# Les colonnes sont séparées par un saut de ligne : un terme tapé ne peut pas
# chevaucher la fin du libellé et le début de la communication.
class AddSearchTextToCashEntries < ActiveRecord::Migration[8.1]
  ACCENTS = "àâäáãåçèéêëìíîïñòóôöõùúûüýÿ".freeze
  SANS_ACCENTS = "aaaaaaceeeeiiiinooooouuuuyy".freeze

  def change
    add_column :cash_entries, :search_text, :virtual, type: :text, stored: true,
               as: "translate(lower(coalesce(label, '') || chr(10) || coalesce(communication, '') " \
                   "|| chr(10) || coalesce(counterparty_name, '')), '#{ACCENTS}', '#{SANS_ACCENTS}')"
  end
end
