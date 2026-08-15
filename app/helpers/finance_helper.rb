module FinanceHelper
  # Où va-t-on pour lever une étape de l'arrêté du mois ?
  #
  # Le service ne connaît pas les routes — il rend un symbole d'intention. Un
  # écran qui dit « il manque quelque chose » sans dire où aller fait perdre le
  # temps qu'il prétend faire gagner : c'est ici qu'on referme cette boucle.
  def monthly_close_action_path(step, month)
    return nil if step.action_path.blank?

    periode = month.strftime("%Y-%m")

    case step.action_path
    when :coda then finance_coda_imports_path
    when :cash_entries then finance_cash_entries_path
    when :unallocated then finance_unallocated_cash_entries_path
    when :recurring then finance_recurring_charges_path(month: periode)
    when :statements then finance_statements_path(month: periode)
    when :trial_balance
      finance_trial_balance_path(from: month.beginning_of_month, to: month.end_of_month)
    end
  end
end
