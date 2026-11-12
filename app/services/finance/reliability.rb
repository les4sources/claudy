module Finance
  # Jusqu'où les chiffres de la Situation financière sont fiables (Michael,
  # 2026-11-12) : le dernier mois arrêté, et ce qui attend encore d'être classé.
  # Une page d'administrateurs qui ne dit pas d'où viennent ses chiffres fait
  # prendre une estimation pour un fait.
  #
  # `MonthClosing` est encore GLOBAL (toutes structures) : l'arrêté par
  # structure viendra avec le verrou du mois.
  class Reliability
    def last_closing
      return @last_closing if defined?(@last_closing)

      @last_closing = MonthClosing.ordered.first
    end

    # Le dernier jour du dernier mois arrêté, ou nil.
    def closed_through = last_closing&.period_month&.end_of_month

    def pending_count = pending_scope.count

    # La somme des lignes à classer, entrées et sorties confondues : l'ordre de
    # grandeur de ce qui peut encore bouger.
    def pending_cents = pending_scope.sum("ABS(cash_entries.amount_cents)")

    def pending? = pending_count.positive?

    private

    def pending_scope = CashEntry.pending
  end
end
