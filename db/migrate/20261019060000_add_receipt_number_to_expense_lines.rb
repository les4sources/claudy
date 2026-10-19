# Le numéro qu'on écrit sur un ticket remis sur papier (Michael, 2026-10-19) :
# la compta reçoit une farde de tickets et doit retrouver la ligne de chacun.
# Il est figé à l'attribution — un numéro déjà écrit à la main ne bouge plus.
class AddReceiptNumberToExpenseLines < ActiveRecord::Migration[8.1]
  def change
    add_column :expense_lines, :receipt_number, :integer
  end
end
