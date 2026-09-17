module Finance
  # Le rapprochement d'une ligne bancaire sortante avec une note de frais ou de
  # mission qui attend son virement (epic #241, phase 3).
  #
  # **Ce service ne crée AUCUNE allocation** (invariant B4, comme
  # `SuggestAllocations` et `MatchPurchaseInvoices`) : il propose, il motive, un
  # humain clique. Une machine qui affecte seule finit par affecter mal, et
  # personne ne le voit avant l'arrêté.
  #
  # Deux indices, dans cet ordre de confiance. L'IBAN de la contrepartie désigne
  # un compte, pas une coïncidence — mais il est chiffré au repos (`humans.iban`,
  # décision 7), la comparaison se fait donc en mémoire, sur les seules notes
  # `processing`, qui se comptent en dizaines. Le montant exact reste une
  # présomption : deux personnes peuvent rendre la même somme le même mois.
  #
  # Calqué sur `Finance::MatchPurchaseInvoices` : même forme, même écran, même
  # geste — l'équipe n'a pas à apprendre deux vocabulaires pour le même travail.
  class MatchExpenseReports
    Match = Struct.new(:report, :beneficiary, :due_cents, :reason, :confidence, keyword_init: true)

    IBAN_CONFIDENCE   = 95
    AMOUNT_CONFIDENCE = 70

    def initialize(reports: nil)
      @reports = reports
    end

    def for_entry(entry)
      return [] unless entry.amount_cents.negative?
      return [] if entry.cash_allocations.any?

      montant = entry.amount_cents.abs
      iban = normalized(entry.counterparty_iban)

      reports.filter_map do |report|
        du = report.remaining_cents
        next unless du.positive?

        if iban.present? && normalized(report.payable_iban) == iban
          Match.new(report: report, beneficiary: report.payable_beneficiary, due_cents: du,
                    reason: "L'IBAN de la ligne est celui de #{report.payable_beneficiary}",
                    confidence: IBAN_CONFIDENCE)
        elsif du == montant
          Match.new(report: report, beneficiary: report.payable_beneficiary, due_cents: du,
                    reason: "#{report.payable_label} attend exactement ce montant",
                    confidence: AMOUNT_CONFIDENCE)
        end
      end.sort_by { |match| -match.confidence }
    end

    # Une passe sur toute une page : les notes `processing` sont chargées UNE
    # fois. Les recharger ligne à ligne est ce qui avait fait tomber l'écran
    # « À affecter » à l'issue #202.
    def for_entries(entries)
      entries.each_with_object({}) do |entry, hash|
        matches = for_entry(entry)
        hash[entry.id] = matches if matches.any?
      end
    end

    private

    def reports
      @reports ||= ExpenseReport.to_pay
                                .includes(:human, :legal_entity, :expense_lines, :cash_allocations)
                                .to_a
    end

    def normalized(iban) = iban.to_s.gsub(/\s+/, "").upcase.presence
  end
end
