# Le justificatif d'une dépense arrive soit en fichier, soit sur papier
# (Michael, 2026-10-18) : la case dit à la compta qu'elle le recevra en main
# propre, au lieu de le chercher en vain dans Claudy.
class AddReceiptOnPaperToExpenseLines < ActiveRecord::Migration[8.1]
  def change
    add_column :expense_lines, :receipt_on_paper, :boolean, default: false, null: false
  end
end
