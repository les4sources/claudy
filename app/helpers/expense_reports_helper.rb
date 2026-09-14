module ExpenseReportsHelper
  # Un montant d'écran, toujours à deux décimales. `Money#format` supprime les
  # centimes ronds — « 124 € » dans une colonne qui contient « 119,20 € » se lit
  # comme une coquille, pas comme un montant.
  def expense_amount(cents)
    Money.new(cents.to_i, "EUR").format(no_cents_if_whole: false)
  end
end
