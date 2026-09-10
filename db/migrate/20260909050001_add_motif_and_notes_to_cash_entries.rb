# Epic #243, phase 2 — la feuille de caisse.
#
# `notes` : la feuille papier porte une glose par ligne (« payé en chèques ALE »).
# Elle n'est ni le libellé ni la communication bancaire — c'est ce qu'on écrit
# dans la marge, et c'est souvent la seule chose qui permet, trois mois plus
# tard, de retrouver pourquoi la caisse ne tombe pas juste.
#
# `cash_motif_id` : le motif retenu à la saisie, à titre de MÉMOIRE. L'affectation
# comptable reste une COPIE sur l'allocation (décision 4) — modifier un motif ne
# doit jamais réécrire une ligne passée. Cette référence ne sert qu'à afficher
# « Bar » ou « Épicerie » dans la colonne Motif de la feuille.
class AddMotifAndNotesToCashEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :cash_entries, :notes, :text
    add_reference :cash_entries, :cash_motif, foreign_key: true, null: true
  end
end
