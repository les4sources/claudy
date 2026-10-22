module Finance
  # Le rapprochement d'une ligne bancaire sortante avec un relevé de dépôt-vente
  # qui attend son virement (epic #248, phase 3).
  #
  # Le relevé réglé entrait dans « À payer », et son paiement devait le solder
  # par rapprochement — mais la file « À affecter » ne le proposait jamais : on
  # suivait la suggestion de Jev (619105, les anciens virements « Volontariat »
  # de la même artisane) et le relevé restait dû (ligne #12216, Eline,
  # octobre 2026).
  #
  # **Ce service ne crée AUCUNE allocation** (invariant B4, comme
  # `MatchCarrierStatements`) : il propose, il motive, un humain clique.
  #
  # Trois indices, dans cet ordre de confiance : la référence du relevé
  # (DV-202610-1) dans la communication, que le virement a recopiée depuis
  # « À payer » ; l'IBAN du contrat de l'artisan ; le montant exact, simple
  # présomption.
  class MatchConsignmentReports
    Match = Struct.new(:report, :beneficiary, :due_cents, :reason, :confidence, keyword_init: true)

    REFERENCE_CONFIDENCE = 98
    IBAN_CONFIDENCE      = 95
    AMOUNT_CONFIDENCE    = 70

    def initialize(reports: nil)
      @reports = reports
    end

    def for_entry(entry)
      return [] unless entry.amount_cents.negative?
      return [] if entry.cash_allocations.any?

      montant = entry.amount_cents.abs
      iban = normalized(entry.counterparty_iban)
      texte = [entry.communication, entry.label].compact.join(" ").upcase

      reports.filter_map do |report|
        du = report.remaining_cents
        next unless du.positive?

        if texte.include?(report.reference.upcase)
          match(report, du, "La communication porte la référence #{report.reference}", REFERENCE_CONFIDENCE)
        elsif iban.present? && normalized(report.payable_iban) == iban
          match(report, du, "L'IBAN de la ligne est celui du contrat de #{report.payable_beneficiary}", IBAN_CONFIDENCE)
        elsif du == montant
          match(report, du, "#{report.payable_label} attend exactement ce montant", AMOUNT_CONFIDENCE)
        end
      end.sort_by { |m| -m.confidence }
    end

    # Une passe sur toute une page : les relevés à régler sont chargés UNE fois.
    def for_entries(entries)
      entries.each_with_object({}) do |entry, hash|
        matches = for_entry(entry)
        hash[entry.id] = matches if matches.any?
      end
    end

    private

    def match(report, du, reason, confidence)
      Match.new(report: report, beneficiary: report.payable_beneficiary, due_cents: du,
                reason: reason, confidence: confidence)
    end

    # Les mêmes que la file « À payer » : en mode virement, vérifiés et
    # comptabilisés. En mode facture, c'est la facture d'achat qui se propose.
    def reports
      @reports ||= ConsignmentReport.awaiting_settlement
                                    .includes(:consignor, :journal_entries, :cash_allocations)
                                    .to_a
                                    .select(&:awaiting_transfer?)
    end

    def normalized(iban) = iban.to_s.gsub(/\s+/, "").upcase.presence
  end
end
