# La recherche des lignes de trésorerie (`CashEntry.matching`) : journal, file
# « À affecter », ventilation de l'épicerie. Un `LIKE '%terme%'` sur trois
# colonnes passées par `translate(lower(...))` relisait toute la table à chaque
# frappe : ~100 ms à 12 000 lignes, ~400 ms à 100 000, et la file le paie deux
# fois par page (compteur + page) et encore après chaque geste.
#
# Un index trigramme par colonne, sur l'expression EXACTE de la requête : le
# planificateur combine les trois (BitmapOr) et tombe à quelques millisecondes.
# Les chaînes d'accents doivent rester identiques à `CashEntry::ACCENTS` et
# `CashEntry::SANS_ACCENTS`, sinon l'index n'est plus utilisé — c'est ce que
# vérifie `spec/models/cash_entry_spec.rb`. En dessous de trois lettres, pas de
# trigramme : la recherche relit la table, comme avant.
class AddTrigramSearchIndexesToCashEntries < ActiveRecord::Migration[8.1]
  ACCENTS = "àâäáãåçèéêëìíîïñòóôöõùúûüýÿ".freeze
  SANS_ACCENTS = "aaaaaaceeeeiiiinooooouuuuyy".freeze
  COLUMNS = %w[label communication counterparty_name].freeze

  def change
    enable_extension "pg_trgm"

    COLUMNS.each do |column|
      add_index :cash_entries,
                "translate(lower(coalesce(#{column}, '')), '#{ACCENTS}', '#{SANS_ACCENTS}') gin_trgm_ops",
                using: :gin, name: "index_cash_entries_on_#{column}_trgm"
    end
  end
end
